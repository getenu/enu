import std/[os, strformat, importutils, options]
import pkg/compiler/ast except new_node
import pkg/compiler/[vm, vmdef, lineinfos]
from pkg/compiler/options import ConfigRef
import core, eval

export Interpreter, VmArgs, set_result

log_scope:
  topics = "scripting"

const STDLIB_PATHS =
  [".", "core", "pure", "pure/collections", "pure/concurrency", "std", "fusion"]

private_access ScriptCtx

proc init*(_: type Interpreter, script_dir, vmlib: string): Interpreter =
  let std_paths = STDLIB_PATHS.map_it join_path(vmlib, "stdlib", it)
  let source_paths = std_paths & join_path(vmlib, "enu") & @[script_dir]
  {.gcsafe.}:
    result = create_interpreter(
      "main.nim",
      source_paths,
      defines = @{"nimscript": "true", "nimconfig": "true"},
    )
    result.config.max_loop_iterations_vm = int.high
    result.config.notes.incl(warnUnusedImportX)
    result.config.notes.incl(hintXDeclaredButNotUsed)

proc pause*(ctx: ScriptCtx) =
  ctx.pause_requested = true

proc rebase_call_depth(self: ScriptCtx, tos: PStackFrame) =
  # The VM's call-depth budget is a single countdown on the shared PCtx —
  # dec'd on every call, inc'd on every return, error at 0. Every yielded
  # script parks its stack mid-call and holds its decrements, so the budget
  # tracks the sum of all parked stacks (and leaks permanently when a parked
  # context is discarded by a reload or error). With enough animated units
  # the counter drains and every script in the level fails at once with
  # "maximum call depth for the VM exceeded". Rebase it to this stack's real
  # depth at each VM entry so the limit applies per script.
  let c =
    if ?self.ctx:
      self.ctx
    elif ?self.interpreter:
      PCtx(self.interpreter.get_graph.vm)
    else:
      nil
  if c.is_nil:
    return
  var depth = 0
  var frame = tos
  while not frame.is_nil:
    inc depth
    frame = frame.next
  c.call_depth = c.config.max_call_depth_vm - depth

proc load*(self: ScriptCtx, file_name, code: string) =
  self.ctx = nil
  self.pc = 0
  self.tos = nil
  self.code = code
  self.module_name = file_name.split_file.name
  self.file_name = file_name

  self.dependencies = @[]

proc run*(self: ScriptCtx): bool =
  private_access ScriptCtx
  self.exit_code = none(int)

  var raw_dependencies = newSeq[string]()
  # Breadcrumb for a rare, traceless worker-thread SIGSEGV (read-from-nil) seen
  # during the player's first script load, inside load_module. It's ~1-in-50 and
  # disappears under a debugger or --stacktrace:on (a timing-sensitive Heisenbug),
  # so a live backtrace has been unobtainable. This log flushes before the crash
  # (proven: the prior "loading script" line always survives), so on recurrence the
  # last line records which input was nil. Cheap — run() fires once per (re)load,
  # not per frame. If this shows a nil here, that's the culprit; if all non-nil,
  # the nil is deeper in the compiler (graph/idgen/module state).
  info "script run: entering load_module",
    file = self.file_name,
    interpreter_nil = self.interpreter.is_nil,
    pass_context_nil = self.pass_context.is_nil,
    code_len = self.code.len
  try:
    self.rebase_call_depth(nil)
    self.interpreter.load_module(
      self.file_name, self.code, self.pass_context, raw_dependencies
    )
    result = false
  except VMPause:
    private_access ScriptCtx
    result = self.exit_code.is_none
  except Exception as e:
    self.running = false
    self.exit_code = some(99)
    raise VMQuit.new_exception("Unhandled err", e)
  finally:
    self.dependencies = @[]
    let script_dir = self.file_name.split_file.dir
    for dep in raw_dependencies:
      if dep == "players":
        continue
      let expected_path = script_dir / (dep & ".nim")
      if file_exists(expected_path):
        self.dependencies.add(expected_path.relative_path(script_dir))

proc eval*(self: ScriptCtx, code: string): Option[string] =
  self.exit_code = none(int)

  try:
    var
      ctx = self.ctx
      pc = self.pc
      tos = self.tos
    self.rebase_call_depth(nil)
    result = self.interpreter.eval(self.pass_context, self.file_name, code)
    self.ctx = ctx
    self.pc = pc
    self.tos = tos
  except VMPause:
    discard
  except CatchableError:
    self.running = false
    self.exit_code = some(99)
    raise

proc call_proc*(
    self: ScriptCtx, proc_name: string, args: varargs[PNode, `to_node`]
): tuple[paused: bool, result: PNode] =
  let foreign_proc =
    self.interpreter.select_routine(proc_name, module_name = self.module_name)
  if foreign_proc == nil:
    raise new_exception(
      VMError, \"script does not export a proc of the name: '{proc_name}'"
    )
  result =
    try:
      {.gcsafe.}:
        (false, self.interpreter.call_routine(foreign_proc, args))
    except VMPause:
      (self.exit_code.is_none, nil)
    except CatchableError:
      self.running = false
      self.exit_code = some(99)
      raise
    except Defect:
      self.running = false
      self.exit_code = some(99)
      raise

proc get_var*(self: ScriptCtx, var_name: string, module_name: string): PNode =
  let sym =
    self.interpreter.select_unique_symbol(var_name, module_name = module_name)
  self.interpreter.get_global_value(sym)

proc resume*(self: ScriptCtx): bool =
  assert not self.ctx.is_nil
  assert self.pc > 0
  assert not self.tos.is_nil

  trace "resuming", script = self.file_name, module = self.module_name
  self.rebase_call_depth(self.tos)
  result =
    try:
      {.gcsafe.}:
        discard exec_from_ctx(self.ctx, self.pc, self.tos)
      false
    except VMPause:
      self.exit_code.is_none
    except CatchableError:
      self.running = false
      self.exit_code = some(99)
      raise
    except Defect:
      self.running = false
      self.exit_code = some(99)
      raise
