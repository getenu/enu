import std/[os, strformat, importutils, options, monotimes, times]
import pkg/compiler/ast except new_node
import pkg/compiler/[vm, vmdef, lineinfos, msgs]
from pkg/compiler/vm {.all.} import current_exception_msg, errTooManyIterations
from pkg/compiler/options import ConfigRef
import core, eval, coroutines, vm_exec_state

export Interpreter, VmArgs, set_result

log_scope:
  topics = "scripting"

const STDLIB_PATHS =
  [".", "core", "pure", "pure/collections", "pure/concurrency", "std", "fusion"]

private_access ScriptCtx

proc register_exception_ops(i: Interpreter) =
  # vmops only registers these under -d:nimcore, which also gives scripts
  # host file and env access. 2.4's VM needs them to bind `except E as e`.
  let c = PCtx(i.get_graph.vm)
  c.register_callback "stdlib.system.getCurrentException",
    proc(a: VmArgs) {.nimcall.} =
      set_result_ref(a, a.current_exception)
  c.register_callback "stdlib.system.getCurrentExceptionMsg",
    proc(a: VmArgs) {.nimcall.} =
      set_result(
        a, current_exception_msg(cast[PCtx](a.ctxp), a.current_exception)
      )
  c.register_callback "stdlib.system.raiseDefect",
    proc(a: VmArgs) {.nimcall.} =
      discard

proc init*(
    _: type Interpreter, script_dir, vmlib: string, fuel: int
): Interpreter =
  let std_paths = STDLIB_PATHS.map_it join_path(vmlib, "stdlib", it)
  let source_paths = std_paths & join_path(vmlib, "enu") & @[script_dir]
  {.gcsafe.}:
    result = create_interpreter(
      "main.nim",
      source_paths,
      defines = @{"nimscript": "true", "nimconfig": "true"},
    )
    # The VM's loop budget (decremented on every backward jump and call) is
    # the watchdog for scripts that never yield. Each script has its own
    # copy, refilled whenever it resumes.
    result.config.max_loop_iterations_vm = fuel
    result.config.notes.incl(warnUnusedImportX)
    result.config.notes.incl(hintXDeclaredButNotUsed)
    result.register_exception_ops()

proc vm(self: ScriptCtx): PCtx =
  PCtx(self.interpreter.get_graph.vm)

proc pause*(ctx: ScriptCtx) =
  ## Park the script once the current host call returns. See `after_host_call`.
  ctx.pause_requested = true

proc running_task(self: ScriptCtx): ScriptTask =
  if self.tasks.len > 0:
    result = self.tasks[^1]

proc seal_top_level(task: ScriptTask) =
  # Each new top-level statement is generated over the trailing `opcEof` of
  # the last one. Code parked inside top-level code still needs its `opcEof`,
  # so leave a spare after it for the next statement to replace.
  let c = task.exec.vm
  c.code.add TInstr(TInstrType(opcEof))
  c.debug.add c.debug[^1]

proc is_script_line(self: ScriptCtx, c: PCtx, info: TLineInfo): bool =
  # The script's file index is found the first time one of its lines turns up.
  let i = info.file_index.int
  if self.file_index < 0 and i >= 0 and i < c.config.m.file_infos.len and
      c.config.m.file_infos[i].full_path.string == self.file_name:
    self.file_index = i
  self.file_index >= 0 and i == self.file_index

proc call_stack*(a: VmArgs): seq[tuple[info: TLineInfo, prc: PSym]] =
  ## The VM's call stack at a host call, innermost first: the call site, then
  ## where each frame was called from.
  let c = cast[PCtx](a.ctxp)
  var frame = a.tos
  result.add (a.current_line_info, frame.prc)
  while ?frame.next:
    result.add (c.debug[frame.comes_from], frame.next.prc)
    frame = frame.next

proc script_line*(self: ScriptCtx, a: VmArgs): TLineInfo =
  ## The innermost line of the script's own file on the call stack: the call
  ## itself, or the script's call into the library code making it.
  let c = cast[PCtx](a.ctxp)
  for (info, _) in a.call_stack:
    if self.is_script_line(c, info):
      return info

proc write_stack_trace*(a: VmArgs) =
  ## Write the VM's call stack, outermost first, like a script error does.
  let c = cast[PCtx](a.ctxp)
  msg_writeln(
    c.config, "stack trace: (most recent call last)", {msg_no_unit_sep}
  )
  let stack = a.call_stack
  for i in countdown(stack.high, 0):
    let (info, prc) = stack[i]
    var s =
      \"{to_filename(c.config, info)}({to_linenumber(info)}, {to_column(info) + ColOffset})"
    if ?prc:
      s.add " ".repeat(max(1, 25 - s.len)) & prc.name.s
    msg_writeln(c.config, s, {msg_no_unit_sep})

proc after_host_call*(ctx: ScriptCtx, a: VmArgs) =
  ## Called by every bridged host proc before it returns to the VM. Acts on a
  ## pause or exit the call asked for. Host calls made outside the script's
  ## own tasks (e.g. state initializers run with the player active) can't
  ## park or unwind it, so they're left alone.
  let task = ctx.running_task
  if not ?task or not task.coroutine.running:
    return
  if ctx.exit_code.is_some:
    raise ScriptExit.new_exception("script exited")
  template park() =
    let line = ctx.script_line(a)
    if line.line > 0:
      ctx.current_line = line
    if task.top_level:
      task.seal_top_level()
    suspend()

  if ctx.pause_requested:
    ctx.pause_requested = false
    park()
  elif task.timed and task.can_park and ctx.park_after > DurationZero and
      get_mono_time() - ctx.resumed_at > ctx.park_after:
    park()
  elif task.timed and ctx.time_limit > DurationZero and
      get_mono_time() - ctx.resumed_at > ctx.time_limit:
    # Reported like the VM's own loop budget running out.
    var line = ctx.script_line(a)
    if line.line == 0:
      line = a.current_line_info
    let c = cast[PCtx](a.ctxp)
    global_error(
      c.config, line, errTooManyIterations % $c.config.max_loop_iterations_vm
    )

proc refuel*(ctx: ScriptCtx, fuel: int) =
  ## Refill the watchdog budget and restart its clock, live if the script is
  ## running.
  ctx.fuel = fuel
  ctx.resumed_at = get_mono_time()
  let task = ctx.running_task
  if ?task and task.coroutine.running:
    task.exec.vm.loop_iterations = fuel

proc finish(self: ScriptCtx, task: ScriptTask) =
  release(task.exec)
  task.coroutine.destroy()
  self.tasks.del(self.tasks.find(task))

proc step(self: ScriptCtx, task: ScriptTask): bool =
  ## Resume `task` until it parks or finishes. True if it finished. Errors
  ## from the script propagate, after the task is cleaned up.
  task.exec.loop_iterations =
    if self.fuel > 0:
      self.fuel.int
    else:
      task.exec.vm.config.max_loop_iterations_vm
  self.resumed_at = get_mono_time()
  swap(task.exec)
  try:
    task.coroutine.resume()
  except ScriptExit:
    discard
  except Exception:
    swap(task.exec)
    self.finish(task)
    self.running = false
    self.exit_code = some(99)
    raise
  swap(task.exec)
  result = task.coroutine.finished or self.exit_code.is_some
  if result:
    self.finish(task)
    if not task.then.is_nil and self.exit_code.is_none:
      task.then()

proc start(
    self: ScriptCtx,
    top_level: bool,
    then: proc() {.gcsafe.},
    timed: bool,
    can_park: bool,
    body: proc(task: ScriptTask),
): ScriptTask =
  ## Start `body` as a new innermost task and run it until it parks or
  ## finishes. The task is returned either way; check `finished`.
  let task = ScriptTask(
    top_level: top_level,
    timed: timed,
    can_park: can_park,
    exec: ExecState.init(self.vm),
    then: then,
  )
  # Top-level work compiles, and the compiler recurses deeply, so it gets a
  # big stack (address space, committed as touched and unmapped when the task
  # ends). Script bodies are what stay parked, so they get small ones.
  let stack_size =
    if top_level:
      64 * 1024 * 1024
    else:
      512 * 1024
  task.coroutine = Coroutine.init(
    proc() {.gcsafe.} =
      # Scripts only run on the worker thread.
      {.gcsafe.}:
        body(task),
    stack_size,
  )
  self.tasks.add task
  discard self.step(task)
  task

proc finished(task: ScriptTask): bool =
  task.coroutine.is_nil or task.coroutine.finished

proc parked(self: ScriptCtx): bool =
  self.tasks.len > 0 and self.exit_code.is_none

proc stop*(self: ScriptCtx) =
  ## Drop the script's tasks, parked or not: before a reload, or when its
  ## thing goes away. Frees their stacks without unwinding them.
  while self.tasks.len > 0:
    let task = self.tasks[^1]
    assert not task.coroutine.running, "can't stop a script from inside itself"
    self.finish(task)

proc load*(self: ScriptCtx, file_name, code: string) =
  self.stop()
  self.code = code
  self.module_name = file_name.split_file.name
  self.file_name = file_name
  self.file_index = -1
  self.current_line = TLineInfo()

  self.dependencies = @[]

proc run*(self: ScriptCtx, me: int): bool =
  ## Load the script's module, then run its body. `me` is the bridge handle of
  ## the thing the script drives. True while the script is parked.
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
  proc run_body() {.gcsafe.} =
    {.gcsafe.}:
      let run_script = self.interpreter.select_routine(
        "run_script", module_name = self.module_name
      )
      if me > 0 and ?run_script:
        discard self.start(
          top_level = false, then = nil, timed = true, can_park = true
        ) do(
          task: ScriptTask
        ):
          discard self.interpreter.call_routine(
            run_script, [new_int_node(nkIntLit, me), new_int_node(nkIntLit, 0)]
          )

  try:
    discard self.start(
      top_level = true, then = run_body, timed = false, can_park = true
    ) do(
      task: ScriptTask
    ):
      # Untimed while compiling; a script's top-level code (all of it,
      # unless it declares a `name`) then runs against the time limit.
      self.interpreter.load_module(
        self.file_name,
        self.code,
        self.pass_context,
        raw_dependencies,
        executing = proc() =
          task.timed = true
          self.resumed_at = get_mono_time(),
      )
    result = self.parked
  except VMQuit:
    # keep its kind: a TIMEOUT mustn't be retried like a transient failure
    self.running = false
    self.exit_code = some(99)
    raise
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
  ## Run `code` in the script's module. If it parks (`forward 5`), it carries
  ## on ahead of the script itself and nothing is returned.
  self.exit_code = none(int)
  var value: Option[string]
  let task = self.start(
    top_level = true, then = nil, timed = true, can_park = false
  ) do(task: ScriptTask):
    value = self.interpreter.eval(self.pass_context, self.file_name, code)
  if task.finished:
    result = value

proc call_proc*(
    self: ScriptCtx, proc_name: string, args: varargs[PNode, `to_node`]
): tuple[paused: bool, result: PNode] =
  let foreign_proc =
    self.interpreter.select_routine(proc_name, module_name = self.module_name)
  if foreign_proc == nil:
    raise new_exception(
      VMError, \"script does not export a proc of the name: '{proc_name}'"
    )
  let args = @args
  let task = self.start(
    top_level = false, then = nil, timed = true, can_park = true
  ) do(
    task: ScriptTask
  ):
    {.gcsafe.}:
      task.result = self.interpreter.call_routine(foreign_proc, args)
  (self.parked, task.result)

proc get_var*(self: ScriptCtx, var_name: string, module_name: string): PNode =
  let sym =
    self.interpreter.select_unique_symbol(var_name, module_name = module_name)
  self.interpreter.get_global_value(sym)

proc resume*(self: ScriptCtx): bool =
  ## Continue the innermost task. True while the script is still parked.
  assert self.tasks.len > 0
  trace "resuming", script = self.file_name, module = self.module_name
  discard self.step(self.tasks[^1])
  self.parked
