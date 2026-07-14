import std/[os, re, posix, sets, options]

import pkg/godot except print
import pkg/compiler/ast except new_node
import
  pkg/compiler/
    [lineinfos, renderer, msgs, vmdef, pathutils, modulegraphs, idents, vm]
from pkg/compiler/vm {.all.} import stack_trace_aux
import godotapi/[spatial, ray_cast, voxel_terrain]
import core, models/[states, bots, builds, things, signs, players]
import libs/[interpreters, eval, fd_tracking]
import ./vars

type ScriptCycleError* = object of VMQuit
  scripts*: seq[string]

proc init*(
    _: type ScriptCtx,
    owner: Thing,
    clone_of: Thing = nil,
    interpreter: Interpreter,
): ScriptCtx =
  result = ScriptCtx(
    module_name: if ?clone_of: clone_of.id else: "",
    interpreter: interpreter,
    fuel: int64.high,
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

proc script_error*(self: Worker, thing: Thing, e: ref VMQuit) =
  var msg = e.msg
  if ?e.parent:
    msg = e.parent.msg

  info "vm error", msg, file = thing.script_ctx.file_name
  for i, error in thing.errors.value:
    var error = error
    error.log = true
    thing.errors[i] = error

  thing.global_flags += HIGHLIGHT_ERROR
  thing.global_flags -= SCRIPT_INITIALIZING
  thing.ensure_visible

  if e of ScriptCycleError:
    let cycle_err = (ref ScriptCycleError)(e)
    for script_name in cycle_err.scripts:
      for u in state.things:
        if ?u.script_ctx and
            u.script_ctx.file_name.extract_filename == script_name:
          u.global_flags += HIGHLIGHT_ERROR
          u.ensure_visible

  # In test mode, a script that fails to load/run (after retries) counts
  # toward the run's failure total. Accumulated on the worker and folded into
  # the exit code when the run finishes — see the test-mode block in worker.nim.
  if TEST_MODE in state.local_flags:
    inc self.test_error_count
    self.test_last_activity = get_mono_time()

proc init_interpreter*[T](self: Worker, _: T) {.gcsafe.} =
  private_access ScriptCtx

  var interpreter =
    Interpreter.init(state.config.script_dir, state.config.lib_dir / "vmlib")

  let controller = self

  # module_names tracks modules successfully loaded into the CURRENT
  # interpreter (script wrappers only import those). A fresh interpreter has
  # none — carrying the old set over makes every wrapper import modules that
  # aren't compiled yet, which falls back to compiling the raw script files
  # off disk and fails on unwrapped user code (issue #51).
  self.module_names.clear()

  self.interpreter = interpreter
  interpreter.config.spell_suggest_max = 0

  interpreter.register_error_hook proc(
      config, info, msg, severity: auto
  ) {.gcsafe.} =
    var info = info
    var msg = msg

    let ctx = controller.active_thing.script_ctx
    let errors = controller.active_thing.errors
    if severity == Severity.Error and config.error_counter >= config.error_max:
      # While retrying (level load / new-thing batch), a failure here may just
      # be an as-yet-unloaded cross-script dependency that resolves on a later
      # pass. Don't echo it as an error; if it's genuinely broken, the thing
      # stays in `failed` and script_error reports it once retries are done.
      if not controller.retry_failures:
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

  interpreter.enter_hook = proc(
      c: PCtx, pc: int, tos: PStackFrame, instr: TInstr
  ) =
    assert ?controller
    assert ?controller.active_thing
    assert ?controller.active_thing.script_ctx

    let ctx = controller.active_thing.script_ctx

    ctx.ctx = c
    ctx.pc = pc
    ctx.tos = tos

    let info = c.debug[pc]
    # The old wall-clock watchdog batched its check behind a byte counter to
    # avoid a get_mono_time() per instruction; a fuel decrement is just another
    # field write next to the ctx.pc/tos writes above, so check it directly.
    ctx.fuel -= 1
    if ctx.fuel <= 0:
      raise (ref VMQuit)(
        info: info,
        kind: TIMEOUT,
        msg:
          \"Timeout. Script {ctx.script} executed too many instructions " &
          "without yielding (instruction budget exhausted)",
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

proc load_script*(self: Worker, thing: Thing, fuel = script_fuel) =
  if SCRIPT_LOADING in thing.global_flags:
    # Re-entry on the same thing is a bug — an Ed callback fired during a
    # script load that drove back through load_level → retry_failed_scripts.
    # Crash with as much context as possible so we can diagnose.
    let outer = if self.active_thing.is_nil: "<nil>" else: self.active_thing.id
    error "load_script re-entered",
      thing_id = thing.id,
      script = thing.script_ctx.script,
      outer_active_thing = outer,
      stack = get_stack_trace()
    logger("err",
      "load_script re-entered for " & thing.id & " (outer active=" & outer &
      "); see log for stack trace.")
    raise (ref AssertionDefect)(
      msg: "load_script re-entered for " & thing.id & "; outer active=" & outer
    )
  thing.global_flags += SCRIPT_LOADING
  defer:
    thing.global_flags -= SCRIPT_LOADING
  let ctx = thing.script_ctx
  try:
    self.active_thing = thing
    thing.errors.clear
    thing.global_flags -= HIGHLIGHT_ERROR

    if not state.paused:
      let module_name = ctx.script.split_file.name
      let script_dir = ctx.script.split_file.dir
      # Only import modules that have already successfully loaded (they're
      # added to module_names at the end of a successful load, below). An
      # import of a not-yet-loaded thing resolves to its RAW script file (the
      # scripts dir is on the VM search path) — unwrapped user code with no
      # API in scope — and fails with confusing built-in-symbol errors
      # ('undeclared identifier: speed'). A real cross-script reference to a
      # not-yet-loaded thing now fails on the user's own symbol instead, and
      # converges through the normal retry pass. (github issue #51)
      var others = self.module_names
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
      let code = thing.code_template(imports)

      # Write generated code to a 'generated' dir for tooling like nimlangserver
      # — but only for project scripts. Files loaded from outside the project
      # (e.g. the bundled players.nim) are evaluated for the VM but never written
      # to disk, so we don't scribble into the shipped library.
      if not script_dir.starts_with(state.config.lib_dir / "vmlib"):
        let generated_dir = script_dir.parentDir / "generated"
        create_dir(generated_dir)
        write_file(generated_dir / module_name & ".nim", code)

      ctx.fuel = fuel
      ctx.file_index = -1
      info "loading script", script = ctx.script
      ctx.load(ctx.script, code)

    if not state.paused:
      ctx.fuel = fuel
      ctx.running = ctx.run()
      debug "script fuel consumed", script = ctx.script,
        consumed = fuel - ctx.fuel

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
        for u in state.things:
          if u.script_ctx != nil and
              u.script_ctx.file_name.extract_filename == node:
            for dep in u.script_ctx.dependencies:
              visit(dep)
            break
        temp_visited.excl(node)

      visit(ctx.file_name.extract_filename)

      # Loaded successfully: other things' wrappers may now import this module.
      self.module_names.incl ctx.module_name

      if not ctx.running and not ?thing.clone_of:
        thing.collect_garbage
        thing.ensure_visible
  except VMQuit as e:
    ctx.running = false
    self.interpreter.reset_module(thing.script_ctx.module_name)
    self.module_names.excl thing.script_ctx.module_name
    if self.retry_failures and e.kind != TIMEOUT:
      # One calm line per transient failure; the detail is DEBUG. If the
      # retries exhaust, script_error reports it loudly.
      info "script failed, will retry",
        script = thing.script_ctx.script.extract_filename
      debug "script failure detail",
        script = thing.script_ctx.script, error = e.msg
      self.failed.add (thing, e)
    else:
      if e.kind == TIMEOUT and thing.errors.value.len == 0:
        thing.errors.add (e.msg, e.info, e.location, false)
      self.script_error(thing, e)
  finally:
    self.active_thing = nil

proc retry_failed_scripts*(self: Worker) {.gcsafe.} =
  sample_open_fds()
  info "retry_failed_scripts entry", fds = open_fd_count()
  var prev_failed: self.failed.type = @[]
  while prev_failed.len != self.failed.len:
    prev_failed = self.failed
    self.failed = @[]
    for f in prev_failed:
      debug "retrying", script = f.thing.script_ctx.script
      self.load_script(f.thing)
  sample_open_fds()
  info "retry_failed_scripts exit", fds = open_fd_count()

  if prev_failed.len == self.failed.len and self.failed.len > 0:
    debug "retry loop terminated because no progress was made",
      failed_count = self.failed.len

  for f in prev_failed:
    self.script_error(f.thing, f.e)
  self.failed = @[]

proc load_script_and_dependents*(self: Worker, thing: Thing) =
  var things_to_reload: HashSet[Thing]
  things_to_reload.incl thing

  state.push_flag LOADING_SCRIPT
  self.retry_failures = true

  var previous_count = 0
  while things_to_reload.card != previous_count:
    previous_count = things_to_reload.card
    for other in state.things.value:
      if other notin things_to_reload and ?other.script_ctx:
        for dep in other.script_ctx.dependencies:
          # dependencies are full paths. Check if they match any reloading thing's file.
          var found = false
          for reloading in things_to_reload:
            if reloading.script_ctx.file_name == dep:
              found = true
              break
          if found:
            things_to_reload.incl other
            break

  for other in things_to_reload:
    if other != thing:
      debug "resetting", module = other.script_ctx.module_name
      self.interpreter.reset_module(other.script_ctx.module_name)
      self.module_names.excl other.script_ctx.module_name

  debug "loading thing", thing_id = thing.id
  self.load_script(thing)

  for other in things_to_reload:
    if other != thing:
      other.code_value.touch Code.init(other.code.nim)

  self.retry_failed_scripts()
  self.retry_failures = false
  state.pop_flag LOADING_SCRIPT

proc script_file_for*(self: Thing): string =
  if self.id == state.player.id:
    state.config.lib_dir & "/vmlib/enu/players.nim"
  elif not ?self.clone_of:
    state.config.script_dir / self.id & ".nim"
  else:
    ""

proc eval*(self: Worker, thing: Thing, code: string): Option[string] =
  let active = self.active_thing
  self.active_thing = thing
  defer:
    self.active_thing = active

  thing.script_ctx.fuel = script_fuel
  {.gcsafe.}:
    result = thing.script_ctx.eval(code)
