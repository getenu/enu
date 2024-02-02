import std/options
import compiler/[syntaxes, reorder, vmdef, msgs]
import compiler/passes {.all.}

{.warning[UnusedImport]: off.}
include compiler/[nimeval, pipelines]

export Interpreter, VmArgs, PCtx, PStackFrame, TLineInfo

# NOTE: This file is mostly made up of modified functions pulled from the nim
# compiler, and must be updated occasionally to keep up with changes to the vm.
# To make diffing easier, the original casing has been preserved, so this file
# is in `camelCase` rather than `snake_case` like the rest of the project.

# adapted from
# https://github.com/nim-lang/Nim/blob/v2.0.2/compiler/pipelines.nim#L88
# Normal module loading procedure, but makes PContext a param so it can be
# passed to extend_module
proc processModule*(
    graph: ModuleGraph,
    module: PSym,
    idgen: IdGenerator,
    stream: PLLStream,
    ctx: var PContext,
): bool {.discardable.} =
  if graph.stopCompile():
    return true
  let bModule = setupEvalGen(graph, module, idgen)

  var
    p: Parser
    s: PLLStream
    fileIdx = module.fileIdx

  prepareConfigNotes(graph, module)
  if stream == nil:
    let filename = toFullPathConsiderDirty(graph.config, fileIdx)
    s = llStreamOpen(filename, fmRead)
    if s == nil:
      rawMessage(graph.config, errCannotOpenFile, filename.string)
      return false
  else:
    s = stream

  while true:
    syntaxes.openParser(p, fileIdx, s, graph.cache, graph.config)

    if not belongsToStdlib(graph, module) or (
      belongsToStdlib(graph, module) and module.name.s == "distros"
    ):
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
      var semNode = semWithPContext(ctx, sl)
      discard processPipeline(graph, semNode, bModule)

    closeParser(p)
    if s.kind != llsStdIn:
      break

  assert graph.pipelinePass == EvalPass
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
    result =
      selectUniqueSymbol(
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

proc loadModule*(
    i: Interpreter, fileName, code: string, ctx: var PContext
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
    discard processModule(i.graph, module, i.idgen, stream, ctx)

# adapted from
# https://github.com/nim-lang/Nim/blob/v2.0.2/compiler/pipelines.nim#L88
proc extendModule*(
    graph: ModuleGraph,
    module: PSym,
    idgen: IdGenerator,
    stream: PLLStream,
    ctx: var PContext,
): bool {.discardable.} =
  if graph.stopCompile():
    return true
  let bModule = setupEvalGen(graph, module, idgen)

  var
    p: Parser
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

      var semNode = semWithPContext(ctx, sl)
      discard processPipeline(graph, semNode, bModule)

    closeParser(p)
    if s.kind != llsStdIn:
      break

  result = true

proc eval*(i: Interpreter, ctx: var PContext, fileName, code: string) =
  ## This can also be used to *reload* the script.
  assert i != nil
  var module: PSym
  let moduleName = fileName.splitFile.name
  for iface in i.graph.ifaces:
    if iface.module != nil and iface.module.name.s == moduleName:
      module = iface.module
      break

  assert module != nil, "no valid module selected"
  let s = llStreamOpen(code)
  extendModule(i.graph, module, i.idgen, s, ctx)

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

proc `error_hook=`*(
    i: Interpreter,
    hook:
      proc(config: ConfigRef, info: TLineInfo, msg: string, severity: Severity) {.
        gcsafe
      .},
) =
  i.registerErrorHook(hook)
