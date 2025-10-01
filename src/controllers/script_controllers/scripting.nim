# NOTE: Godot 4 adds infinite loop protection to retry_failed_scripts with
# max_retries limit and associated logging. This prevents hangs when script
# loading is broken.

import std/[os, re, posix]

import gdext
import pkg/compiler/ast except new_node
import pkg/compiler/[lineinfos, renderer, msgs, vmdef]
from pkg/compiler/vm {.all.} import stack_trace_aux
import gdext/classes/[gdnode3d, gdraycast3d, gdvoxelterrain]
import core, models/[states, bots, builds, units, signs, players]
import libs/[interpreters, eval]
import ./vars

proc init*(
    _: type ScriptCtx,
    owner: Unit,
    clone_of: Unit = nil,
    interpreter: Interpreter,
): ScriptCtx =
  result = ScriptCtx(
    module_name: if ?clone_of: clone_of.id else: "",
    interpreter: interpreter,
    timeout_at: MonoTime.high,
    timer: MonoTime.high,
  )

proc extract_file_info(msg: string): tuple[name: string, info: TLineInfo] =
  if msg =~ re"unhandled exception: (.*)\((\d+), (\d+)\)":
    result = (
      matches[0],
      TLineInfo(
        line: matches[1].parse_int.uint16, col: matches[2].parse_int.int16
      ),
    )

proc script_error*(self: Worker, unit: Unit, e: ref VMQuit) =
  var msg = e.msg
  if ?e.parent:
    msg = e.parent.msg

  info "vm error", msg, file = unit.script_ctx.file_name
  for i, error in unit.errors.value:
    var error = error
    error.log = true
    unit.errors[i] = error

  unit.global_flags += HighlightError
  unit.global_flags -= ScriptInitializing
  unit.ensure_visible

proc init_interpreter*[T](self: Worker, _: T) {.gcsafe.} =
  private_access ScriptCtx

  var interpreter =
    Interpreter.init(state.config.script_dir, state.config.lib_dir)

  let controller = self

  self.interpreter = interpreter
  interpreter.config.spell_suggest_max = 0

  interpreter.register_error_hook proc(
      config, info, msg, severity: auto
  ) {.gcsafe.} =
    var info = info
    var msg = msg

    let ctx = controller.active_unit.script_ctx
    let errors = controller.active_unit.errors
    if severity == Severity.Error and config.error_counter >= config.error_max:
      echo msg
      var file_name =
        if info.file_index.int >= 0:
          config.m.file_infos[info.file_index.int].full_path.string
        else:
          "???"

      if file_exists(file_name) and ?ctx.file_name:
        if file_name.get_file_info != ctx.file_name.get_file_info:
          msg_writeln(
            config, "stack trace: (most recent call last)", {msg_no_unit_sep}
          )
          stack_trace_aux(ctx.ctx, ctx.tos, ctx.pc)
          let file_info = extract_file_info msg

          if ?file_info:
            (file_name, info) = file_info
          # discard `raise` SIGINT
          # msg = msg.replace(re"unhandled exception:.*\) Error\: ", "")
        # else:
        # msg = msg.replace(re"(?ms);.*", "")
      else:
        error "File not found handling error", file_name

      var loc = \"{file_name}({int info.line},{int info.col})"
      errors.add (msg, info, loc, false)
      ctx.exit_code = error_code
      raise (ref VMQuit)(info: info, msg: msg, location: loc)

  var count: byte = 0
  interpreter.enter_hook = proc(
      c: PCtx, pc: int, tos: PStackFrame, instr: TInstr
  ) =
    assert ?controller
    assert ?controller.active_unit
    assert ?controller.active_unit.script_ctx

    let ctx = controller.active_unit.script_ctx

    ctx.ctx = c
    ctx.pc = pc
    ctx.tos = tos

    let info = c.debug[pc]
    inc count
    if count == 255:
      # don't call get_mono_time for every instruction for a 5-10% speedup.
      count = 0
      let now = get_mono_time()
      if ctx.timeout_at < now:
        let duration = script_timeout
        raise (ref VMQuit)(
          info: info,
          kind: Timeout,
          msg:
            \"Timeout. Script {ctx.script} executed for too long without " &
            \"yielding: {duration}",
        )

    # We don't care about the line info if we're not in our enu script.
    # Store the file index the first time we hit our file and only change
    # current_line/previous_line if the current instruction has that index.
    if ctx.file_index == -1 and info.file_index.int >= 0 and
        info.file_index.int < interpreter.config.m.file_infos.len:
      let file_name =
        interpreter.config.m.file_infos[info.file_index.int].full_path.string
      if file_name == ctx.file_name:
        ctx.file_index = info.file_index.int
    elif ctx.file_index == info.file_index.int:
      if ctx.previous_line != info:
        (ctx.previous_line, ctx.current_line) = (ctx.current_line, info)

    if ctx.pause_requested:
      ctx.pause_requested = false
      raise VMPause.new_exception("vm paused")

proc load_script*(self: Worker, unit: Unit, timeout = script_timeout) =
  let ctx = unit.script_ctx
  try:
    self.active_unit = unit
    unit.errors.clear
    unit.global_flags -= HighlightError

    if not state.paused:
      let module_name = ctx.script.split_file.name
      var others = self.module_names
      self.module_names.incl module_name
      others.excl module_name
      let imports =
        if others.card > 0:
          "import " & others.to_seq.join(", ")
        else:
          ""
      let code = unit.code_template(imports)
      ctx.timeout_at = get_mono_time() + timeout
      ctx.file_index = -1
      info "loading script", script = ctx.script
      ctx.load(ctx.script, code)

    if not state.paused:
      ctx.timeout_at = get_mono_time() + timeout
      ctx.running = ctx.run()
      if not ctx.running and not ?unit.clone_of:
        unit.collect_garbage
        unit.ensure_visible
  except VMQuit as e:
    ctx.running = false
    self.interpreter.reset_module(unit.script_ctx.module_name)
    if self.retry_failures and e.kind != Timeout:
      self.failed.add (unit, e)
    else:
      self.script_error(unit, e)
  finally:
    self.active_unit = nil

proc retry_failed_scripts*(self: Worker) {.gcsafe.} =
  var prev_failed: self.failed.type = @[]
  var retry_count = 0
  const max_retries = 3 # Prevent infinite loops when script loading is broken

  while prev_failed.len != self.failed.len and retry_count < max_retries:
    prev_failed = self.failed
    self.failed = @[]
    retry_count += 1
    info "retry attempt", count = retry_count, failed_scripts = prev_failed.len

    for f in prev_failed:
      info "retrying script for unit", unit_id = f.unit.id
      self.load_script(f.unit)

  if retry_count >= max_retries:
    warn "Script retry limit reached - stopping to prevent infinite loop",
      failed_scripts = self.failed.len

  for f in prev_failed:
    self.script_error(f.unit, f.e)
  self.failed = @[]

proc load_script_and_dependents*(self: Worker, unit: Unit) =
  var previous: HashSet[Unit]
  var units_by_module: Table[string, Unit]
  var units_to_reload: HashSet[Unit]

  units_to_reload.incl unit
  state.push_flag LoadingScript
  self.retry_failures = true

  for other in state.units.value:
    if ?other.script_ctx:
      units_by_module[other.script_ctx.module_name] = other

  while units_to_reload != previous:
    previous = units_to_reload
    for unit in previous:
      for dep in unit.script_ctx.dependents:
        units_to_reload.incl units_by_module[dep]

  for other in units_to_reload:
    if other != unit:
      debug "resetting", module = other.script_ctx.module_name
      self.interpreter.reset_module(other.script_ctx.module_name)

  debug "loading unit", unit_id = unit.id
  self.load_script(unit)

  for other in units_to_reload:
    if other != unit:
      other.code_value.touch Code.init(other.code.nim)

  self.retry_failed_scripts()
  self.retry_failures = false
  state.pop_flag LoadingScript

proc script_file_for*(self: Unit): string =
  if self.id == state.player.id:
    state.config.lib_dir & "/enu/client/players.nim"
  elif not ?self.clone_of:
    state.config.script_dir / self.id & ".nim"
  else:
    ""

proc eval*(self: Worker, unit: Unit, code: string) =
  let active = self.active_unit
  self.active_unit = unit
  defer:
    self.active_unit = active

  unit.script_ctx.timeout_at = get_mono_time() + script_timeout
  {.gcsafe.}:
    discard unit.script_ctx.eval(code)
