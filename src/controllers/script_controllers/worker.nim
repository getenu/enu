import std/[locks, os, random, net]
import std/times except seconds, minutes
from pkg/netty import Reactor
import core, models, models/[serializers], libs/[interpreters, eval]
import ./[vars, host_bridge, scripting]

var
  worker_lock: locks.Lock
  work_done: locks.Cond

worker_lock.init_lock
work_done.init_cond

proc advance_unit(self: Worker, unit: Unit, timeout: MonoTime): bool =
  let ctx = unit.script_ctx
  if ?ctx and ctx.running:
    unit.current_line = ctx.current_line.line.int
    if unit of Build:
      let unit = Build(unit)
      unit.voxels_remaining_this_frame += unit.voxels_per_frame
    try:
      assert self.active_unit.is_nil
      var task_state = NextTask

      let now = get_mono_time()

      let delta =
        if ?ctx.last_ran:
          (now - ctx.last_ran).in_microseconds.float / 1000000.0
        else:
          0.0

      ctx.last_ran = now
      if ctx.callback == nil or (;
        task_state = ctx.callback(delta, timeout)
        task_state in {Done, NextTask}
      ):
        ctx.timer = MonoTime.high
        ctx.action_running = false
        self.active_unit = unit
        ctx.timeout_at = now + script_timeout
        ctx.running = ctx.resume()
        if not ctx.running and not ?unit.clone_of:
          unit.collect_garbage
          unit.ensure_visible
          unit.current_line = 0

        result = ctx.running and task_state == NextTask
      elif now >= ctx.timer:
        ctx.timer = now + advance_step
        ctx.saved_callback = ctx.callback
        ctx.callback = nil
        self.active_unit = unit
        ctx.timeout_at = now + script_timeout
        discard ctx.resume()
    except VMQuit as e:
      self.interpreter.reset_module(unit.script_ctx.module_name)
      self.script_error(unit, e)
    finally:
      self.active_unit = nil

proc change_code(self: Worker, unit: Unit, code: Code) =
  debug "code changing", unit = unit.id
  unit.errors.clear
  unit.local_flags -= HighlightError
  if ?unit.script_ctx and unit.script_ctx.running and not ?unit.clone_of:
    unit.collect_garbage

  var edits = unit.shared.edits
  for id in edits.value.keys:
    if id != unit.id and edits[id].len == 0:
      let edit = edits[id]
      edits.del id
      edit.destroy

  unit.reset()
  state.pop_flag ConsoleVisible
  if LoadingScript notin state.local_flags and code.nim.strip == "":
    self.interpreter.reset_module(unit.script_ctx.module_name)
    debug "reset module", module = unit.script_ctx.module_name
    unit.script_ctx.running = false
    self.module_names.excl unit.script_ctx.module_name
    remove_file unit.script_ctx.script
  elif code.nim.strip != "":
    debug "loading unit", unit_id = unit.id
    if LoadingScript notin state.local_flags and not self.retry_failures:
      write_file(unit.script_ctx.script, code.nim)
      if not self.interpreter.is_nil:
        self.load_script_and_dependents(unit)
      else:
        # We load the player before we init the interpreter to get to an
        # interactive state quicker. Otherwise this shouldn't ever be nil.
        assert unit.id == state.player.id
    else:
      self.load_script(unit)

proc watch_code(self: Worker, unit: Unit) =
  unit.code_value.changes:
    if added or touched:
      if change.item.owner == "" or change.item.owner == Zen.thread_ctx.id:
        save_level(state.config.level_dir)
        self.change_code(unit, change.item)
      elif Server in state.local_flags:
        if change.item.nim == "":
          remove_file unit.script_ctx.script
        else:
          write_file(unit.script_ctx.script, change.item.nim)

  unit.eval_value.changes:
    if added or touched and change.item != "":
      unit.eval = ""
      try:
        self.eval(unit, change.item)
      except VMQuit as e:
        self.script_error(unit, e)

  if unit.script_ctx.is_nil:
    unit.script_ctx =
      ScriptCtx.init(owner = unit, interpreter = self.interpreter)

    unit.script_ctx.script = script_file_for unit

proc watch_units(
    self: Worker,
    units: ZenSeq[Unit],
    parent: Unit,
    body:
      proc(unit: Unit, change: Change[Unit], added: bool, removed: bool) {.
        gcsafe
      .},
) {.gcsafe.} =
  units.track proc(changes: seq[Change[Unit]]) {.gcsafe.} =
    for change in changes:
      let unit = change.item
      let added = Added in change.changes
      let removed = Removed in change.changes
      body(unit, change, added, removed)
      if added:
        # FIXME: this is being set for the main thread in node_controller
        unit.fix_parents(parent)
        unit.frame_created = state.frame_count
        unit.collisions.track proc(changes: seq[Change[(string, Vector3)]]) =
          unit.script_ctx.timer = get_mono_time()
        self.watch_units(unit.units, unit, body)

template for_all_units(self: Worker, body: untyped) {.dirty.} =
  self.watch_units state.units,
    parent = nil,
    proc(
        unit: Unit, change: Change[Unit], added: bool, removed: bool
    ) {.gcsafe.} =
      body

proc worker_thread(params: (ZenContext, GameState)) {.gcsafe.} =
  let (ctx, main_thread_state) = params
  worker_lock.acquire

  var listen_address = main_thread_state.config.listen_address
  let worker_ctx =
    ZenContext.init(
      id = \"work-{generate_id()}",
      chan_size = 500,
      buffer = false,
      listen_address = listen_address,
      label = "worker",
    )

  Zen.thread_ctx = worker_ctx
  ctx.subscribe(Zen.thread_ctx)

  state = GameState.init_from(main_thread_state)
  let connect_address = main_thread_state.config.connect_address
  if ?listen_address or not ?connect_address:
    state.push_flag Server

  state.config_value = ZenValue[Config](Zen.thread_ctx["config"])
  state.console = ConsoleModel.init_from(main_thread_state.console)
  state.worker_ctx_name = worker_ctx.id
  main_thread_state.worker_ctx_name = worker_ctx.id

  state.player = Player.init
  state.player.color = state.config.player_color

  work_done.signal
  worker_lock.release

  var worker = Worker()

  worker.for_all_units:
    if added:
      unit.worker_thread_joined
      worker.watch_code unit

    if removed:
      worker.unmap_unit(unit)
      if not ?unit.clone_of and ?unit.script_ctx:
        worker.module_names.excl unit.script_ctx.module_name
      if ?unit.script_ctx:
        unit.script_ctx.running = false
        unit.script_ctx.callback = nil
        if not (unit of Player) and LoadingScript notin state.local_flags and
            not ?unit.clone_of:
          remove_file unit.script_ctx.script
          remove_dir unit.data_dir

      for zid in unit.zids:
        debug "untracking zid", zid, unit = unit.id
        Zen.thread_ctx.untrack zid
      unit.zids = @[]
      unit.destroy

  let player = state.player
  # add player before interpreter is initialized to get to an interactive
  # state quicker
  if Server in state.local_flags:
    state.units.add player
  else:
    state.push_flag(Connecting)
    let tmp_path = join_path(state.config.work_dir, "tmp")
    create_dir tmp_path
    state.config_value.value:
      script_dir = tmp_path

  worker.init_interpreter("")
  worker.bridge_to_vm

  if Server in state.local_flags:
    var level_dir = state.config.level_dir
    player.script_ctx.interpreter = worker.interpreter
    worker.load_script_and_dependents(player)

    worker.load_level(level_dir)
    state.level_name = state.config.world & "/" & state.config.level
    state.config_value.changes:
      if added:
        if change.item.level_dir != level_dir:
          let full_reset = ResettingVM in state.local_flags
          if level_dir != "":
            save_level(level_dir, save_all = full_reset)
          worker.unload_level()
          if full_reset:
            worker.init_interpreter("")
            worker.bridge_to_vm
            player.script_ctx.interpreter = worker.interpreter
            worker.load_script_and_dependents(player)
          level_dir = change.item.level_dir
          if level_dir != "":
            worker.load_level(level_dir)
  else:
    var timeout_at = get_mono_time() + 30.seconds
    var connected = false
    while not connected and get_mono_time() < timeout_at:
      try:
        Zen.thread_ctx.subscribe(connect_address)
        connected = true
      except ConnectionError:
        discard
    if not connected:
      fail \"Unable to connect to server at {connect_address}"
    state.pop_flag(Connecting)
    state.units.add player
    player.script_ctx.interpreter = worker.interpreter
    worker.load_script_and_dependents(player)

  var sign =
    Sign.init(
      "",
      "",
      width = 4,
      height = 3.05,
      owner = state.player,
      size = 244,
      billboard = true,
      text_only = true,
      transform = Transform.init(origin = vec3(0, 4, 0)),
    )

  state.player.units += sign
  sign.global_flags -= Visible
  sign.local_flags += Hide

  var running = true

  state.local_flags.changes:
    if Quitting.added:
      save_level(state.config.level_dir)
      state.pop_flag Quitting
      running = false
    elif NeedsRestart.added:
      running = false

  const max_time = (1.0 / 120.0).seconds
  const min_time = (1.0 / 120.0).seconds
  const auto_save_interval = 30.seconds
  const backup_interval = 15.minutes
  var save_at = get_mono_time() + auto_save_interval
  var backup_at = MonoTime.low

  try:
    while running:
      let frame_start = get_mono_time()
      let timeout = frame_start + max_time
      let wait_until = frame_start + min_time

      Zen.thread_ctx.boop
      run_deferred()

      inc state.frame_count
      for ctx_name in Zen.thread_ctx.unsubscribed:
        var i = 0
        while i < state.units.len:
          if state.units[i].id == \"player-{ctx_name}":
            var player = Player(state.units[i])
            state.units.del i
          else:
            i += 1

        if Server notin state.local_flags:
          state.push_flag(NeedsRestart)
          break

      var to_process: seq[Unit]
      state.units.value.walk_tree proc(unit: Unit) =
        to_process.add unit
      to_process.shuffle

      var batched: HashSet[Unit]

      while Zen.thread_ctx.pressure < 0.9 and to_process.len > 0 and
          state.voxel_tasks <= 10 and get_mono_time() < timeout:
        let units = to_process
        to_process = @[]
        for unit in units:
          if Ready in unit.global_flags:
            if unit.batch_changes:
              batched.incl unit
            if worker.advance_unit(unit, timeout):
              to_process.add(unit)

      for unit in batched:
        unit.apply_changes

      let now = get_mono_time()

      if now > save_at:
        save_level(state.config.level_dir)
        save_at = now + auto_save_interval

      if now > backup_at:
        backup_level(state.config.level_dir)
        backup_at = now + backup_interval

      if now < wait_until:
        sleep int((wait_until - get_mono_time()).in_milliseconds)
  except Exception as e:
    error "Unhandled worker thread exception",
      kind = $e.type, msg = e.msg, stacktrace = e.get_stack_trace

    state.push_flag(NeedsRestart)

  try:
    if NeedsRestart in state.local_flags:
      if ?listen_address:
        private_access Reactor
        Zen.thread_ctx.reactor.socket.close
      state.pop_flag NeedsRestart

    Zen.thread_ctx.boop
  except Exception:
    discard

proc launch_worker*(
    ctx: ZenContext, state: GameState
): system.Thread[tuple[ctx: ZenContext, state: GameState]] =
  worker_lock.acquire
  result.create_thread(worker_thread, (ctx, state))
  work_done.wait(worker_lock)
  worker_lock.release
