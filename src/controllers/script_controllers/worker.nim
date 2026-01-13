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

proc handle_catchable_error(
    self: Worker, unit: Unit, e: ref CatchableError
) =
  ## Convert CatchableError to VMQuit and display in console with stack trace
  let ctx = unit.script_ctx
  let info = if ?ctx: ctx.current_line else: TLineInfo()
  let loc = if ?ctx and ?ctx.file_name and info.line > 0:
    \"{ctx.file_name}({int info.line},{int info.col})"
  else:
    ""
  # Add error to unit.errors for console display (similar to error_hook)
  unit.errors.add (e.msg, info, loc, false)
  if ?ctx:
    ctx.exit_code = error_code
    ctx.running = false
  let vm_error = (ref VMQuit)(
    info: info,
    kind: Unknown,
    msg: e.msg,
    location: loc
  )
  if ?ctx:
    self.interpreter.reset_module(ctx.module_name)
  self.script_error(unit, vm_error)

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
          if unit of Build:
            Build(unit).end_asap()
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
    except CatchableError as e:
      self.handle_catchable_error(unit, e)
    finally:
      self.active_unit = nil

proc change_code(self: Worker, unit: Unit, code: Code) =
  debug "code changing", unit = unit.id
  unit.errors.clear
  unit.global_flags -= HighlightError
  if ?unit.script_ctx and unit.script_ctx.running and not ?unit.clone_of:
    unit.collect_garbage

  var edits = unit.shared.edits
  for id in edits.value.keys:
    if id != unit.id and edits[id].len == 0:
      let edit = edits[id]
      edits.del id
      edit.destroy

  unit.reset()
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
      if Server in state.local_flags:
        save_level(state.config.level_dir)
        self.change_code(unit, change.item)
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

  unit.zids.add:
    unit.errors.changes:
      if unit.code.owner == Zen.thread_ctx.id:
        if added and change.item.log:
          state.err(
            \"[url=unit://{unit.id}]{change.item.msg} {unit.errors.len}[/url]"
          )
          state.push_flags ConsoleVisible

        if removed:
          state.pop_flags ConsoleVisible

  if unit.script_ctx.is_nil:
    unit.script_ctx =
      ScriptCtx.init(owner = unit, interpreter = self.interpreter)

    unit.script_ctx.script = script_file_for unit

proc watch_units(
    self: Worker,
    units: ZenSeq[Unit],
    parent: Unit,
    body: proc(unit: Unit, change: Change[Unit], added: bool, removed: bool) {.
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
  let worker_ctx = ZenContext.init(
    id = \"work-{generate_id()}",
    chan_size = 500,
    buffer = false,
    listen_address = listen_address,
    label = "worker",
  )

  Zen.thread_ctx = worker_ctx
  ctx.subscribe(Zen.thread_ctx)

  state = GameState.init_from(main_thread_state)
  state.init_logger
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

  let load_level = proc() =
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

  if Server in state.local_flags:
    load_level()
  else:
    var timeout_at = get_mono_time() + 30.seconds
    var connected = false
    when defined(zen_debug_messages):
      echo "=== Client objects before connect ==="
      for id in Zen.thread_ctx.objects.keys:
        echo "  ", id
      echo "=== End pre-connect objects ==="
    while not connected and get_mono_time() < timeout_at:
      try:
        Zen.thread_ctx.subscribe(connect_address)
        connected = true
        echo "=== Connected to server. Initial bytes: sent=", Zen.thread_ctx.bytes_sent, " received=", Zen.thread_ctx.bytes_received
        when defined(zen_debug_messages):
          Zen.thread_ctx.dump_message_stats("client after connect")
      except ConnectionError:
        discard

    state.pop_flag(Connecting)
    state.units.add player
    player.script_ctx.interpreter = worker.interpreter
    if not connected:
      state.err \"Unable to connect to server at {connect_address}"
      state.config_value.value:
        connect_address = ""
      state.push_flag Server
      load_level()
    else:
      worker.load_script_and_dependents(player)

  var sign = Sign.init(
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
  if NeedsRestart in state.local_flags:
    running = false

  state.local_flags.changes:
    if Quitting.added:
      save_level(state.config.level_dir)
      # In test mode, don't pop the flag - let the main thread's force_quit_at
      # timeout handle it. This ensures test_exit_code has time to propagate.
      if TestMode notin state.local_flags:
        state.pop_flag Quitting
      running = false
    elif NeedsRestart.added:
      running = false

  state.config_value.changes:
    if added:
      discard  # let uc = state.config.build_user_config
      # save_user_config(uc)  # Temporarily disabled

    if state.config.player_color != change.item.player_color:
      player.color = state.config.player_color

  const max_time = (1.0 / 120.0).seconds
  const min_time = (1.0 / 120.0).seconds
  const auto_save_interval = 30.seconds
  const backup_interval = 15.minutes
  const test_timeout = 5.minutes
  const bytes_log_interval = 5.seconds
  var save_at = get_mono_time() + auto_save_interval
  var backup_at = MonoTime.low
  var test_started_at = MonoTime.high
  var last_bytes_log = MonoTime.low
  var last_bytes_sent = 0
  var last_bytes_received = 0
  var last_snapshots_flushed = 0
  var last_deltas_flushed = 0
  var tick_count = 0
  var last_tick_count = 0
  var max_tick_time = Duration.default

  try:
    while running:
      let frame_start = get_mono_time()
      let timeout = frame_start + max_time
      let wait_until = frame_start + min_time
      inc tick_count

      var to_process: seq[Unit]
      state.units.value.walk_tree proc(unit: Unit) =
        if ?unit.script_ctx:
          if unit.script_ctx.running:
            unit.global_flags += ScriptRunning
          else:
            unit.global_flags -= ScriptRunning
        to_process.add unit

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
        try:
          unit.apply_changes
        except CatchableError as e:
          worker.handle_catchable_error(unit, e)

      # Apply changes for all Builds not already processed, to ensure packed chunks are flushed
      # This handles the case where voxels are drawn before Ready is set
      if packed_chunks_enabled():
        state.units.value.walk_tree proc(unit: Unit) =
          if unit of Build and unit notin batched:
            let build = Build(unit)
            if build.voxels.dirty_chunks.len > 0 or build.voxels.batching:
              build.apply_changes()

      # Process rate-limited snapshot queues
      if packed_chunks_enabled():
        state.snapshots_flushed_this_frame = 0
        let global_limit = if state.global_snapshots_per_frame > 0:
                             state.global_snapshots_per_frame
                           else:
                             int.high

        state.units.value.walk_tree proc(unit: Unit) =
          if unit of Build:
            let build = Build(unit)
            if build.voxels.is_flushing:
              let per_build = if build.voxels.snapshots_per_frame > 0:
                                build.voxels.snapshots_per_frame
                              else:
                                int.high
              let remaining = global_limit - state.snapshots_flushed_this_frame
              let limit = min(per_build, remaining)

              if limit > 0:
                let flushed = build.voxels.flush_next_snapshots(limit)
                state.snapshots_flushed_this_frame += flushed

                # If done flushing and was in ASAP mode, clear flag
                if not build.voxels.is_flushing and ASAPMode in build.local_flags:
                  build.local_flags -= ASAPMode

      Zen.thread_ctx.tick
      run_deferred()

      # Update network stats for main thread
      state.net_bytes_sent = Zen.thread_ctx.bytes_sent
      state.net_bytes_received = Zen.thread_ctx.bytes_received
      if not Zen.thread_ctx.reactor.isNil:
        state.net_connections = Zen.thread_ctx.reactor.connections.len
      else:
        state.net_connections = 0

      # Log bytes sent/received and snapshot/delta stats periodically
      if frame_start > last_bytes_log + bytes_log_interval:
        let sent = Zen.thread_ctx.bytes_sent
        let recv = Zen.thread_ctx.bytes_received
        let sent_delta = sent - last_bytes_sent
        let recv_delta = recv - last_bytes_received

        # Collect snapshot/delta stats from all builds
        var total_snapshots = 0
        var total_deltas = 0
        state.units.value.walk_tree proc(unit: Unit) =
          if unit of Build:
            let build = Build(unit)
            total_snapshots += build.voxels.snapshots_flushed
            total_deltas += build.voxels.deltas_flushed

        let snapshots_delta = total_snapshots - last_snapshots_flushed
        let deltas_delta = total_deltas - last_deltas_flushed
        let ticks_delta = tick_count - last_tick_count
        let ticks_per_sec = ticks_delta.float / bytes_log_interval.in_seconds.float

        if sent_delta > 0 or recv_delta > 0 or snapshots_delta > 0 or deltas_delta > 0 or ticks_delta > 0:
          echo "=== Worker: ", ticks_per_sec.int, " ticks/s, max=", max_tick_time.in_milliseconds, "ms | Bytes: sent=", sent, " (+", sent_delta, "), recv=", recv, " (+", recv_delta, ") | Snapshots: ", total_snapshots, " (+", snapshots_delta, "), Deltas: ", total_deltas, " (+", deltas_delta, ")"
        last_bytes_log = frame_start
        last_bytes_sent = sent
        last_bytes_received = recv
        last_snapshots_flushed = total_snapshots
        last_deltas_flushed = total_deltas
        last_tick_count = tick_count
        max_tick_time = Duration.default

      # In test mode, exit when all scripts have finished
      if TestMode in state.local_flags:
        if test_started_at == MonoTime.high:
          test_started_at = get_mono_time()
          echo "=== Test mode: started ==="

        var any_running = false
        var running_scripts: seq[string]
        state.units.value.walk_tree proc(unit: Unit) =
          if ?unit.script_ctx and unit.script_ctx.running:
            any_running = true
            running_scripts.add unit.id

        let elapsed = get_mono_time() - test_started_at
        # Log progress every 30 seconds
        if elapsed.in_seconds.int mod 30 == 0 and elapsed.in_seconds.int > 0 and
            elapsed.in_milliseconds.int mod 1000 < 100:
          echo "=== Test mode: still running after ", elapsed, " scripts=", running_scripts, " ==="

        if not any_running:
          let exit_code = if state.test_exit_code < 0: 0 else: state.test_exit_code
          echo "=== Test mode: all scripts finished, exit_code=", exit_code, " elapsed=", elapsed, " ==="
          state.test_exit_code = exit_code
          state.push_flag Quitting
        elif elapsed > test_timeout:
          echo "=== Test mode: TIMEOUT after ", elapsed, " scripts=", running_scripts, " ==="
          state.test_exit_code = 1
          state.push_flag Quitting

      inc state.frame_count

      let now = get_mono_time()

      if now > save_at:
        save_level(state.config.level_dir)
        Zen.thread_ctx.tick_keepalives()
        save_at = now + auto_save_interval

      if now > backup_at and TestMode notin state.local_flags:
        backup_level(state.config.level_dir)
        Zen.thread_ctx.tick_keepalives()
        backup_at = now + backup_interval

      # Track max tick time for debugging
      let tick_time = get_mono_time() - frame_start
      if tick_time > max_tick_time:
        max_tick_time = tick_time

      if now < wait_until:
        sleep int((wait_until - get_mono_time()).in_milliseconds)
  except Exception as e:
    error "Unhandled worker thread exception",
      kind = $e.type, msg = e.msg, stacktrace = e.get_stack_trace

    # Re-raise to crash properly instead of restarting
    raise e
    # state.push_flag(NeedsRestart)

  try:
    if NeedsRestart in state.local_flags:
      if ?listen_address:
        private_access Reactor
        Zen.thread_ctx.reactor.socket.close
      state.pop_flag NeedsRestart

    Zen.thread_ctx.tick
  except Exception:
    discard

proc launch_worker*(
    ctx: ZenContext, state: GameState
): system.Thread[tuple[ctx: ZenContext, state: GameState]] =
  worker_lock.acquire
  result.create_thread(worker_thread, (ctx, state))
  work_done.wait(worker_lock)
  worker_lock.release
