import std/[os, strformat, importutils]
import pkg/compiler/ast except new_node
import pkg/compiler/[vm, vmdef]
import core, eval

export Interpreter, VmArgs, set_result

log_scope:
  topics = "scripting"

const STDLIB_PATHS = [
  ".", "core", "pure", "pure/collections", "pure/concurrency", "std", "fusion"
]

private_access ScriptCtx

proc init*(_: type Interpreter, script_dir, vmlib: string): Interpreter =
  let std_paths = STDLIB_PATHS.map_it join_path(vmlib, "stdlib", it)
  let source_paths = std_paths & join_path(vmlib, "enu") & @[script_dir]
  {.gcsafe.}:
    result =
      create_interpreter(
        "base_api.nim",
        source_paths,
        defines = @{"nimscript": "true", "nimconfig": "true"},
      )
    result.config.max_loop_iterations_vm = int.high

proc pause*(ctx: ScriptCtx) =
  ctx.pause_requested = true

proc load*(self: ScriptCtx, file_name, code: string) =
  self.ctx = nil
  self.pc = 0
  self.tos = nil
  self.code = code
  self.module_name = file_name.split_file.name
  self.file_name = file_name

proc run*(self: ScriptCtx): bool =
  private_access ScriptCtx
  self.exit_code = none(int)

  try:
    self.interpreter.load_module(self.file_name, self.code, self.pass_context)

    result = false
  except VMPause:
    private_access ScriptCtx
    result = self.exit_code.is_none
  except CatchableError as e:
    self.running = false
    self.exit_code = some(99)
    raise VMQuit.new_exception("Unhandled err", e)

proc eval*(self: ScriptCtx, code: string): bool =
  self.exit_code = none(int)

  try:
    var
      ctx = self.ctx
      pc = self.pc
      tos = self.tos
    self.interpreter.eval(self.pass_context, self.file_name, code)
    self.ctx = ctx
    self.pc = pc
    self.tos = tos
    result = false
  except VMPause:
    result = self.exit_code.is_none
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

proc get_var*(self: ScriptCtx, var_name: string, module_name: string): PNode =
  let sym =
    self.interpreter.select_unique_symbol(var_name, module_name = module_name)
  self.interpreter.get_global_value(sym)

proc resume*(self: ScriptCtx): bool =
  assert not self.ctx.is_nil
  assert self.pc > 0
  assert not self.tos.is_nil

  trace "resuming", script = self.file_name, module = self.module_name
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
