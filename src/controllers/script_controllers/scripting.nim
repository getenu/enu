import std/[os, re, posix, sets, options]

import pkg/godot except print
import pkg/compiler/ast except new_node
import
  pkg/compiler/
    [lineinfos, renderer, msgs, vmdef, pathutils, modulegraphs, idents, vm]
from pkg/compiler/vm {.all.} import stack_trace_aux
import godotapi/[spatial, ray_cast, voxel_terrain]
import core, models/[states, bots, builds, units, signs, players]
import libs/[interpreters, eval]
import ./vars

type ScriptCycleError* = object of VMQuit
  scripts*: seq[string]

# Counts nested host -> VM -> host -> VM re-entries from exec_instance.
# Lets us correlate defects with re-entry depth.
var rawExecute_depth* {.threadvar.}: int

proc dump_vm_state_on_defect*(unit: Unit, e: ref Exception) =
  ## Capture as much VM state as possible at the moment the Defect was
  ## caught. The frame state is mutated by reset_module and subsequent
  ## error handling, so this has to happen FIRST.
  private_access ScriptCtx
  let ctx = unit.script_ctx
  if ctx.is_nil:
    info "DEFECT_DUMP no script_ctx", msg = e.msg, unit = unit.id
    return
  let c = ctx.ctx
  let tos = ctx.tos
  let pc = ctx.pc

  info "DEFECT_DUMP",
    msg = e.msg, unit = unit.id, depth = rawExecute_depth, pc

  if c.is_nil or tos.is_nil:
    info "DEFECT_DUMP no vm state",
      ctx_nil = c.is_nil, tos_nil = tos.is_nil
    return

  if pc >= 0 and pc < c.code.len:
    let instr = c.code[pc]
    info "DEFECT_DUMP opcode",
      opcode = $instr.opcode,
      regA = instr.regA.int,
      regB = instr.regB.int,
      regC = instr.regC.int,
      pc

  var f = tos
  var level = 0
  while f != nil:
    let prc = f.prc
    let name = if prc.is_nil: "<nil>" else: prc.name.s
    let pinfo =
      if prc.is_nil:
        VmProcInfo(usedRegisters: -1, pc: 0)
      else:
        c.procToCodePos.getOrDefault(prc.id, VmProcInfo(usedRegisters: -1))
    info "DEFECT_DUMP frame",
      level,
      prc = name,
      slots_len = f.slots.len,
      cached_usedRegisters = pinfo.usedRegisters.int,
      cached_pc = pinfo.pc.int,
      comesFrom = f.comesFrom
    f = f.next
    inc level

  info "DEFECT_DUMP stack_trace", trace = e.get_stack_trace

  # Bytecode window around the failing pc — useful for diagnosing
  # future VM defects (which slot index in which opcode blew up).
  try:
    var lines = newSeq[string]()
    let from_pc = max(0, pc - 5)
    let to_pc = min(c.code.len - 1, pc + 5)
    for p in from_pc .. to_pc:
      let i = c.code[p]
      lines.add $p & ":" & $i.opcode & "/" & $i.regA.int & "/" &
        $i.regB.int & "/" & $i.regC.int & (if p == pc: "  <==" else: "")
    info "DEFECT_DUMP bytecode_window", window = lines.join(" | ")
  except CatchableError as e2:
    info "DEFECT_DUMP bytecode_window failed", msg = e2.msg

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

  unit.global_flags += HIGHLIGHT_ERROR
  unit.global_flags -= SCRIPT_INITIALIZING
  unit.ensure_visible

  if e of ScriptCycleError:
    let cycle_err = (ref ScriptCycleError)(e)
    for script_name in cycle_err.scripts:
      for u in state.units:
        if ?u.script_ctx and
            u.script_ctx.file_name.extract_filename == script_name:
          u.global_flags += HIGHLIGHT_ERROR
          u.ensure_visible

  # In test mode, track script errors for exit code
  if TEST_MODE in state.local_flags:
    if state.test_exit_code < 0:
      state.test_exit_code = 1
    else:
      state.test_exit_code = state.test_exit_code + 1

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

      var full_file_name = file_name
      if not file_name.is_absolute and file_name != "???":
        full_file_name = state.config.level_dir / "generated" / file_name

      if file_exists(full_file_name) and ?ctx.file_name:
        let reported_info = get_file_info(full_file_name)
        if reported_info != get_file_info(ctx.file_name):
          msg_writeln(
            config, "stack trace: (most recent call last)", {msg_no_unit_sep}
          )
          stack_trace_aux(ctx.ctx, ctx.tos, ctx.pc)
          let file_info = extract_file_info msg

          if ?file_info:
            (file_name, info) = file_info
          # discard `raise` SIGINT
          # msg = msg.replace(re"unhandled exception:.*\) Error\: ", "")
        else:
          file_name = full_file_name
        # else:
        # msg = msg.replace(re"(?ms);.*", "")
      else:
        error "File not found handling error",
          file_name,
          full_path = full_file_name,
          level_dir = state.config.level_dir

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
          kind: TIMEOUT,
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
  if SCRIPT_LOADING in unit.global_flags:
    # Re-entry on the same unit is a bug — an Ed callback fired during a
    # script load that drove back through load_level → retry_failed_scripts.
    # Crash with as much context as possible so we can diagnose.
    let outer = if self.active_unit.is_nil: "<nil>" else: self.active_unit.id
    error "load_script re-entered",
      unit_id = unit.id,
      script = unit.script_ctx.script,
      outer_active_unit = outer,
      stack = get_stack_trace()
    logger("err",
      "load_script re-entered for " & unit.id & " (outer active=" & outer &
      "); see log for stack trace.")
    raise (ref AssertionDefect)(
      msg: "load_script re-entered for " & unit.id & "; outer active=" & outer
    )
  unit.global_flags += SCRIPT_LOADING
  defer:
    unit.global_flags -= SCRIPT_LOADING
  let ctx = unit.script_ctx
  try:
    self.active_unit = unit
    unit.errors.clear
    unit.global_flags -= HIGHLIGHT_ERROR

    if not state.paused:
      let module_name = ctx.script.split_file.name
      let script_dir = ctx.script.split_file.dir
      var others = self.module_names
      self.module_names.incl module_name
      others.excl module_name
      # Only inject imports for modules whose script files exist in the current
      # script dir. Stale entries (e.g. from a previous level) are silently
      # dropped rather than causing "cannot open file" errors.
      var valid_others: HashSet[string]
      for name in others:
        if file_exists(script_dir / name & ".nim"):
          valid_others.incl(name)
      let imports =
        if valid_others.card > 0:
          "import " & valid_others.to_seq.join(", ")
        else:
          ""
      let code = unit.code_template(imports)

      # Write generated code to a 'generated' directory for tooling like
      # nimlangserver.
      let generated_dir = script_dir.parentDir / "generated"
      create_dir(generated_dir)
      let generated_file = generated_dir / module_name & ".nim"
      try:
        write_file(generated_file, code)
      except IOError:
        # Surface as much OS-level context as possible before re-raising.
        let err = errno
        let dir_exists = dir_exists(generated_dir)
        let file_exists = file_exists(generated_file)
        var dir_perms = ""
        var dir_owner = ""
        try:
          let info = get_file_info(generated_dir)
          dir_perms = $info.permissions
        except CatchableError:
          discard
        error "writeFile failed",
          path = generated_file,
          unit_id = unit.id,
          errno = err,
          strerror = $strerror(err),
          generated_dir = generated_dir,
          generated_dir_exists = dir_exists,
          generated_file_exists = file_exists,
          generated_dir_permissions = dir_perms,
          script_loading_flag = (SCRIPT_LOADING in unit.global_flags),
          script_initializing_flag =
            (SCRIPT_INITIALIZING in unit.global_flags),
          stack = get_stack_trace()
        logger("err",
          "writeFile failed for " & generated_file & " (errno=" & $err &
          " " & $strerror(err) & "); see log for details.")
        raise

      ctx.timeout_at = get_mono_time() + timeout
      ctx.file_index = -1
      info "loading script", script = ctx.script
      ctx.load(ctx.script, code)

    if not state.paused:
      ctx.timeout_at = get_mono_time() + timeout
      ctx.running = ctx.run()

      var temp_visited: HashSet[string]
      proc visit(node: string) =
        if node in temp_visited:
          let msg = "Circular dependency detected involving script: " & node
          var scripts: seq[string] = @[]
          for v in temp_visited:
            scripts.add(v)
          scripts.add(node)
          raise (ref ScriptCycleError)(msg: msg, scripts: scripts)
        temp_visited.incl(node)
        for u in state.units:
          if u.script_ctx != nil and
              u.script_ctx.file_name.extract_filename == node:
            for dep in u.script_ctx.dependencies:
              visit(dep)
            break
        temp_visited.excl(node)

      visit(ctx.file_name.extract_filename)

      if not ctx.running and not ?unit.clone_of:
        unit.collect_garbage
        unit.ensure_visible
  except VMQuit as e:
    ctx.running = false
    # If the VMQuit came from interpreters.run wrapping a Defect, the VM
    # frame state is still intact at this point. Dump it before
    # reset_module wipes the module's iface — that's our only window to
    # learn what the bytecode was actually doing when the defect fired.
    if e.parent != nil:
      dump_vm_state_on_defect(unit, e.parent)
    self.interpreter.reset_module(unit.script_ctx.module_name)
    if self.retry_failures and e.kind != TIMEOUT:
      info "retrying failed script later",
        script = unit.script_ctx.script, error = e.msg
      self.failed.add (unit, e)
    else:
      if e.kind == TIMEOUT and unit.errors.value.len == 0:
        unit.errors.add (e.msg, e.info, e.location, false)
      self.script_error(unit, e)
  finally:
    self.active_unit = nil

proc retry_failed_scripts*(self: Worker) {.gcsafe.} =
  var prev_failed: self.failed.type = @[]
  while prev_failed.len != self.failed.len:
    prev_failed = self.failed
    self.failed = @[]
    for f in prev_failed:
      debug "retrying", script = f.unit.script_ctx.script
      self.load_script(f.unit)

  if prev_failed.len == self.failed.len and self.failed.len > 0:
    debug "retry loop terminated because no progress was made",
      failed_count = self.failed.len

  for f in prev_failed:
    self.script_error(f.unit, f.e)
  self.failed = @[]

proc load_script_and_dependents*(self: Worker, unit: Unit) =
  var units_to_reload: HashSet[Unit]
  units_to_reload.incl unit

  state.push_flag LOADING_SCRIPT
  self.retry_failures = true

  var previous_count = 0
  while units_to_reload.card != previous_count:
    previous_count = units_to_reload.card
    for other in state.units.value:
      if other notin units_to_reload and ?other.script_ctx:
        for dep in other.script_ctx.dependencies:
          # dependencies are full paths. Check if they match any reloading unit's file.
          var found = false
          for reloading in units_to_reload:
            if reloading.script_ctx.file_name == dep:
              found = true
              break
          if found:
            units_to_reload.incl other
            break

  for other in units_to_reload:
    if other != unit:
      debug "resetting", module = other.script_ctx.module_name
      self.interpreter.reset_module(other.script_ctx.module_name)

  debug "loading unit", unit_id = unit.id
  # Use longer timeout for first script load (system.nim compilation can be slow)
  let timeout =
    if not self.initial_load_done: initial_script_timeout else: script_timeout
  self.load_script(unit, timeout)
  self.initial_load_done = true

  for other in units_to_reload:
    if other != unit:
      other.code_value.touch Code.init(other.code.nim)

  self.retry_failed_scripts()
  self.retry_failures = false
  state.pop_flag LOADING_SCRIPT

proc script_file_for*(self: Unit): string =
  if self.id == state.player.id:
    state.config.lib_dir & "/enu/players.nim"
  elif not ?self.clone_of:
    state.config.script_dir / self.id & ".nim"
  else:
    ""

proc eval*(self: Worker, unit: Unit, code: string): Option[string] =
  let active = self.active_unit
  self.active_unit = unit
  defer:
    self.active_unit = active

  unit.script_ctx.timeout_at = get_mono_time() + script_timeout
  {.gcsafe.}:
    result = unit.script_ctx.eval(code)
