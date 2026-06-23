import std/[options, os, strutils]
import pkg/pretty
import compiler/[syntaxes, reorder, vmdef, msgs, renderer, vm]
import compiler/passes {.all.}
import compiler/lineinfos

{.warning[UnusedImport]: off.}
include compiler/[nimeval, pipelines]

export Interpreter, VmArgs, PCtx, PStackFrame, TLineInfo

# NOTE: This file is mostly made up of modified functions pulled from the nim
# compiler, and must be updated occasionally to keep up with changes to the vm.
# To make diffing easier, the original casing has been preserved, so this file
# is in `camelCase` rather than `snake_case` like the rest of the project.

# adapted from
# https://github.com/nim-lang/Nim/blob/v2.2.10/compiler/pipelines.nim#L94
# (was originally based on v2.0.2). Normal module loading procedure, but makes
# PContext a param so it can be passed to extend_module.
# Recursive proc to find import statements in AST
proc getImports(n: PNode, result: var seq[PNode]) =
  if n.kind in {nkImportStmt, nkFromStmt}:
    result.add n
  else:
    for i in 0 ..< n.safeLen:
      getImports(n[i], result)

proc processModule*(
    graph: ModuleGraph,
    module: PSym,
    idgen: IdGenerator,
    stream: PLLStream,
    ctx: var PContext,
    dependencies: var seq[string],
): bool {.discardable.} =
  if graph.stopCompile():
    return true
  let bModule = setupEvalGen(graph, module, idgen)

  var
    p: Parser = default(Parser)
    s: PLLStream
    fileIdx = module.fileIdx

  prepareConfigNotes(graph, module)
  graph.config.notes.incl(warnUnusedImportX)
  graph.config.notes.incl(hintXDeclaredButNotUsed)
  let we_opened_stream = stream == nil
  if we_opened_stream:
    let filename = toFullPathConsiderDirty(graph.config, fileIdx)
    s = llStreamOpen(filename, fmRead)
    if s == nil:
      rawMessage(graph.config, errCannotOpenFile, filename.string)
      return false
  else:
    s = stream
  defer:
    # Only close streams we opened — caller-provided streams are theirs
    # to close.
    if we_opened_stream and s != nil:
      llStreamClose(s)

  # Extract dependencies by examining resolved symbols in the typed AST
  var pendingModules = newSeq[string]()

  proc checkModule(ownerSym: PSym) =
    if ownerSym == nil or ownerSym.kind != skModule:
      return
    let modName = ownerSym.name.s
    let depPath =
      toFullPathConsiderDirty(graph.config, ownerSym.info.fileIndex).string

    # Only track sibling build/bot scripts as dependencies.
    if modName notin pendingModules and modName != module.name.s:
      let is_script = "/scripts/" in depPath or "/generated/" in depPath
      if is_script:
        pendingModules.add(modName)

  proc findDependencies(n: PNode) =
    if n == nil:
      return

    if n.kind == nkSym and n.sym != nil:
      let sym = n.sym
      # Only track deps via actual symbol USAGE, not import statement nodes.
      # sym.kind==skModule captures injected imports giving false all-to-all deps.
      if sym.kind != skModule:
        # sym's owner is a sibling build/bot script
        if sym.owner != nil and sym.owner.kind == skModule:
          checkModule(sym.owner)
        # sym's type is defined in a sibling build/bot script
        if sym.typ != nil and sym.typ.sym != nil:
          checkModule(sym.typ.sym.owner)

    for i in 0 ..< n.safeLen:
      findDependencies(n[i])

  while true:
    syntaxes.openParser(p, fileIdx, s, graph.cache, graph.config)

    if not belongsToStdlib(graph, module) or
        (belongsToStdlib(graph, module) and module.name.s == "distros"):
      # XXX what about caching? no processing then? what if I change the
      # modules to include between compilation runs? we'd need to track that
      # in ROD files. I think we should enable this feature only
      # for the interactive mode.
      if module.name.s != "nimscriptapi":
        processImplicitImports graph,
          graph.config.implicitImports, nkImportStmt, module, ctx, bModule,
          idgen
        processImplicitImports graph,
          graph.config.implicitIncludes, nkIncludeStmt, module, ctx, bModule,
          idgen

    checkFirstLineIndentation(p)
    block processCode:
      if graph.stopCompile():
        break processCode
      var n = parseTopLevelStmt(p)
      if n.kind == nkEmpty:
        break processCode
      # read everything, no streaming possible
      var sl = newNodeI(nkStmtList, n.info)
      sl.add n
      while true:
        var n = parseTopLevelStmt(p)
        if n.kind == nkEmpty:
          break
        sl.add n

      prePass(ctx, sl)

      pendingModules.set_len(0)
      var semNode = semWithPContext(ctx, sl)

      findDependencies(semNode)

      # Collect deps before processPipeline so they are preserved even if we pause
      for name in pendingModules:
        if name notin dependencies:
          dependencies.add(name)

      discard processPipeline(graph, semNode, bModule)

    closeParser(p)
    if s.kind != llsStdIn:
      break

  assert graph.pipelinePass == EvalPass
  # Old unusedImports handling logic removed as we processed it above

  # Required: every script's module body must raise VMPause before reaching
  # here (via exit() at the end of build_code_template.nim.nimf and
  # bot_code_template.nim.nimf). If a script completes naturally:
  #   - closePContext below finalizes the PContext and queues generic
  #     instances (eg. class constructors) into finalNode via
  #     addCodeForGenerics
  #   - interpreterCode runs evalStmt+execute on finalNode, which sizes
  #     tos.slots from the current c.prc.regInfo.len -- often smaller
  #     than the bytecode the second-execute ends up touching, surfacing
  #     as cross-script IndexDefects
  #   - that second-execute also causes spawner scripts to re-run their
  #     constructor instantiations, producing unbounded unit growth
  #     (~6.5x over the correct count on the api-test level)
  # Keeping exit() in the templates is the production fix. Removing it
  # without first dropping this finalize sequence will re-introduce both
  # bugs.
  let finalNode = closePContext(graph, ctx, nil)
  discard interpreterCode(bModule, finalNode)

  if graph.config.backend notin {backendC, backendCpp, backendObjc}:
    # We only write rod files here if no C-like backend is active.
    # The C-like backends have been patched to support the IC mechanism.
    # They are responsible for closing the rod files. See `cbackend.nim`.
    closeRodFile(graph, module)
  result = true

# from nimeval. Added moduleName
proc selectUniqueSymbol*(
    i: Interpreter,
    name: string,
    symKinds: set[TSymKind] = {skLet, skVar},
    moduleName: string,
): PSym =
  ## Can be used to access a unique symbol of ``name`` and
  ## the given ``symKinds`` filter.
  assert i != nil
  var module = i.mainModule
  for iface in i.graph.ifaces:
    if iface.module != nil and iface.module.name.s == moduleName:
      module = iface.module
      break
  assert module != nil, "no module selected"
  let n = getIdent(i.graph.cache, name)
  var it: ModuleIter
  var s = initModuleIter(it, i.graph, module, n)
  result = nil
  while s != nil:
    if s.kind in symKinds:
      if result == nil:
        result = s
      else:
        return nil # ambiguous
    s = nextModuleIter(it, i.graph)

# from nimeval. Added moduleName
proc selectRoutine*(i: Interpreter, name: string, module_name: string): PSym =
  ## Selects a declared routine (proc/func/etc) from the main module.
  ## The routine needs to have the export marker ``*``. The only matching
  ## routine is returned and ``nil`` if it is overloaded.
  {.gcsafe.}:
    result = selectUniqueSymbol(
      i,
      name,
      {skTemplate, skMacro, skFunc, skMethod, skProc, skConverter},
      moduleName,
    )

proc resetModule*(i: Interpreter, moduleName: string) =
  for iface in i.graph.ifaces:
    if iface.module != nil and iface.module.name.s == moduleName:
      initStrTables(i.graph, iface.module)
      iface.module.ast = nil
      break

template with_import_stack_recovery(graph: ModuleGraph, body: untyped) =
  ## An aborted compile (a VMQuit timeout raised from the exec hook mid-import)
  ## skips importer.nim's `importStack.setLen(L)` pop, leaving the in-flight
  ## files on the stack — every later import of them then reports "recursive
  ## module dependency", permanently. Worse, those modules sit half-compiled in
  ## the graph and would be treated as loaded with missing symbols. The stack
  ## itself records exactly which modules were mid-compile: on the way out,
  ## pop anything above our depth and reset those modules so the next load
  ## recompiles them from scratch.
  let stack_depth = graph.importStack.len
  try:
    body
  finally:
    while graph.importStack.len > stack_depth:
      let aborted = graph.importStack.pop
      let m = graph.getModule(aborted)
      if m != nil:
        initStrTables(graph, m)
        m.ast = nil

import std/posix

proc loadModule*(
    i: Interpreter,
    fileName, code: string,
    ctx: var PContext,
    dependencies: var seq[string],
) {.gcsafe.} =
  assert i != nil

  var module: PSym
  let moduleName = fileName.splitFile.name
  for iface in i.graph.ifaces:
    if iface.module != nil and iface.module.name.s == moduleName and
        fileName == toFullPath(i.graph.config, iface.module.info):
      module = iface.module
      break

  if module.isNil:
    {.gcsafe.}:
      module = i.graph.makeModule(fileName)

  initStrTables(i.graph, module)
  module.ast = nil
  var stream = llStreamOpen(code)

  # after some kinds of errors the vm will switch back to emStaticStmt mode,
  # which causes "cannot evaluate at compile time" issues with some variables.
  # Force things back to emRepl.
  PCtx(i.graph.vm).mode = emRepl

  ctx = preparePContext(i.graph, module, i.idgen)

  {.gcsafe.}:
    with_import_stack_recovery(i.graph):
      discard processModule(i.graph, module, i.idgen, stream, ctx, dependencies)

proc node_to_str(n: PNode): string =
  case n.kind
  of nkStrLit .. nkTripleStrLit:
    n.strVal
  of nkIntLit .. nkUInt64Lit:
    $n.intVal
  of nkFloatLit .. nkFloat128Lit:
    $n.floatVal
  of nkNilLit:
    "nil"
  else:
    renderTree(n, {renderNoComments})

# adapted from
# https://github.com/nim-lang/Nim/blob/v2.2.10/compiler/pipelines.nim#L94
# (was originally based on v2.0.2).
proc extendModule*(
    graph: ModuleGraph,
    module: PSym,
    idgen: IdGenerator,
    stream: PLLStream,
    ctx: var PContext,
): Option[string] {.discardable.} =
  if graph.stopCompile():
    return
  let bModule = setupEvalGen(graph, module, idgen)

  var
    p: Parser = default(Parser)
    s = stream
    fileIdx = module.fileIdx

  while true:
    syntaxes.openParser(p, fileIdx, s, graph.cache, graph.config)

    checkFirstLineIndentation(p)
    assert graph.pipelinePass == EvalPass
    block processCode:
      if graph.stopCompile():
        break processCode
      var n = parseTopLevelStmt(p)
      if n.kind == nkEmpty:
        break processCode
      # read everything, no streaming possible
      var sl = newNodeI(nkStmtList, n.info)
      sl.add n
      while true:
        var n = parseTopLevelStmt(p)
        if n.kind == nkEmpty:
          break
        sl.add n

      prePass(ctx, sl)

      # `eval` should return the value of a bare trailing expression (e.g.
      # `1 + 1`). The compiler rejects a bare expression in statement context
      # with a single "expression has to be used" error, so we sem with
      # errorMax raised (so it does not quit) and capture errors via the hook.
      # If that is the only error and the node has a value type, we re-run it
      # as an expression below; otherwise the captured errors are replayed so
      # genuine errors still propagate.
      let old_hook = ctx.config.structuredErrorHook
      let old_error_count = ctx.config.errorCounter
      let old_error_max = ctx.config.errorMax
      let old_error_outputs = ctx.config.m.errorOutputs
      ctx.config.errorMax = high(int)
      ctx.config.m.errorOutputs = {}
      type CapturedError = tuple[info: TLineInfo, msg: string, sev: Severity]
      var captured: seq[CapturedError]
      let captured_ptr = captured.addr
      ctx.config.structuredErrorHook = proc(
          config: ConfigRef, info: TLineInfo, msg: string, severity: Severity
      ) {.gcsafe.} =
        {.gcsafe.}: captured_ptr[].add((info, msg, severity))

      var semNode = semWithPContext(ctx, sl)
      let errors_added = ctx.config.errorCounter - old_error_count

      ctx.config.structuredErrorHook = old_hook
      ctx.config.errorMax = old_error_max
      ctx.config.m.errorOutputs = old_error_outputs

      # If exactly one error (the "discard" error) and the node has a non-void
      # type, it's a bare expression — evaluate and return its value.
      # Note: semStmtList unwraps single-element lists, so semNode is the
      # expression directly, not a nkStmtList wrapper.
      if errors_added == 1 and semNode.typ != nil and
          semNode.typ.kind notin {tyVoid, tyError, tyNone}:
        ctx.config.errorCounter = old_error_count
        let r = evalExpr(PCtx(graph.vm), semNode)
        if r != nil and r.kind notin {nkEmpty, nkError}:
          result = some(node_to_str(r))
        break processCode

      # Replay any captured errors through the original hook so they propagate.
      ctx.config.errorCounter = old_error_count
      for e in captured:
        if e.sev == Severity.Error:
          inc ctx.config.errorCounter
        if old_hook != nil:
          old_hook(ctx.config, e.info, e.msg, e.sev)

      discard processPipeline(graph, semNode, bModule)

    closeParser(p)
    if s.kind != llsStdIn:
      break

proc eval*(i: Interpreter, ctx: var PContext, fileName, code: string): Option[string] =
  ## This can also be used to *reload* the script.
  assert i != nil
  var module: PSym
  let moduleName = fileName.splitFile.name
  for iface in i.graph.ifaces:
    if iface.module != nil and iface.module.name.s == moduleName:
      module = iface.module
      break

  assert module != nil, "no valid module selected"
  # If closePContext was called (for scripts that complete without VMPause,
  # e.g. players.nim), restore the context so extendModule can work.
  # closePContext also pops the proc context and owner, both of which must
  # be restored or evalAtCompileTime crashes accessing c.p.owner.
  if ctx.currentScope == nil:
    ctx.currentScope = ctx.topLevelScope
    pushProcCon(ctx, module)
    pushOwner(ctx, module)
  let s = llStreamOpen(code)
  with_import_stack_recovery(i.graph):
    result = extendModule(i.graph, module, i.idgen, s, ctx)

proc config*(i: Interpreter): ConfigRef =
  i.graph.config

proc `exit_hook=`*(
    i: Interpreter, hook: proc(c: PCtx, pc: int, tos: PStackFrame)
) =
  (PCtx i.graph.vm).exitHook = hook

proc `enter_hook=`*(
    i: Interpreter,
    hook: proc(c: PCtx, pc: int, tos: PStackFrame, instr: TInstr),
) =
  (PCtx i.graph.vm).enterHook = hook

proc error_hook*(
    i: Interpreter,
    hook: proc(
      config: ConfigRef, info: TLineInfo, msg: string, severity: Severity
    ) {.gcsafe.},
) =
  i.registerErrorHook(hook)

proc get_graph*(i: Interpreter): ModuleGraph =
  i.graph
