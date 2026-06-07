import std/[locks, os, random, net, json, jsonutils, strutils]
import std/times except seconds, minutes
from pkg/netty import Reactor
import core, models, models/serializers, models/chunk_pager,
  libs/[interpreters, eval]
import ./[vars, host_bridge, scripting]

var
  worker_lock: locks.Lock
  work_done: locks.Cond

worker_lock.init_lock
work_done.init_cond

proc handle_catchable_error(self: Worker, unit: Unit, e: ref Exception) =
  ## Convert host-side exception to VMQuit and display in console.
  ## Accepts Defect as well as CatchableError so VM-level bugs (e.g.
  ## IndexDefect from corrupted register frames after module reset) don't
  ## crash the worker thread.
  let ctx = unit.script_ctx
  let info =
    if ?ctx:
      ctx.current_line
    else:
      TLineInfo()
  let loc =
    if ?ctx and ?ctx.file_name and info.line > 0:
      \"{ctx.file_name}({int info.line},{int info.col})"
    else:
      ""
  # Add error to unit.errors for console display (similar to error_hook)
  unit.errors.add (e.msg, info, loc, false)
  if ?ctx:
    ctx.exit_code = error_code
    ctx.running = false
  let vm_error =
    (ref VMQuit)(info: info, kind: UNKNOWN, msg: e.msg, location: loc)
  if ?ctx:
    self.interpreter.reset_module(ctx.module_name)
  self.script_error(unit, vm_error)

proc advance_unit(self: Worker, unit: Unit, timeout: MonoTime): bool =
  let ctx = unit.script_ctx
  if ?ctx and ctx.running:
    if ASAP_MODE notin unit.global_flags:
      unit.current_line = ctx.current_line.line.int
    if unit of Build:
      let unit = Build(unit)
      unit.voxels_remaining_this_frame += unit.voxels_per_frame
    try:
      assert self.active_unit.is_nil
      var task_state = NEXT_TASK

      let now = get_mono_time()

      let delta =
        if ?ctx.last_ran:
          (now - ctx.last_ran).in_microseconds.float / 1000000.0
        else:
          0.0

      ctx.last_ran = now
      if ctx.callback == nil or (;
        task_state = ctx.callback(delta, timeout)
        task_state in {DONE, NEXT_TASK}
      ):
        ctx.timer = MonoTime.high
        ctx.action_running = false
        self.active_unit = unit
        ctx.timeout_at = now + script_timeout
        ctx.running = ctx.resume()
        if not ctx.running:
          if unit of Build:
            Build(unit).end_asap()
          if not ?unit.clone_of:
            unit.collect_garbage
            unit.ensure_visible
            unit.current_line = 0

        result = ctx.running and task_state == NEXT_TASK
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
    except Defect as e:
      # Bytecode-level defects (e.g. IndexDefect inside vm.nim from a
      # corrupted register frame after module reset) are bugs in the VM/script
      # path, not the host. Treat them as script errors so a single bad script
      # doesn't take down the worker thread.
      dump_vm_state_on_defect(unit, e)
      self.handle_catchable_error(unit, e)
    finally:
      self.active_unit = nil

proc load_unit_from_json(unit_id, json_file: string) =
  let opts = JOptions(allow_missing_keys: true)
  let data_json = read_file(json_file).parse_json
  var new_unit: Unit
  if unit_id.starts_with("bot_"):
    new_unit = data_json.json_to(Bot, opts)
  elif unit_id.starts_with("build_"):
    new_unit = data_json.json_to(Build, opts)
  else:
    error "Unknown unit type for new JSON file", unit_id
    return
  new_unit.global_flags += SCRIPT_INITIALIZING
  dont_join = true
  state.units.add(new_unit)
  load_units(new_unit, @[])
  dont_join = false
  if new_unit of Build:
    Build(new_unit).reset_bounds
    Build(new_unit).restore_edits
  if ?new_unit.script_ctx:
    new_unit.script_ctx.last_saved_json_mtime =
      get_last_modification_time(json_file)
    if file_exists(new_unit.script_ctx.script):
      new_unit.code = Code.init(read_file(new_unit.script_ctx.script))
    else:
      new_unit.global_flags -= SCRIPT_INITIALIZING

proc write_script_file(unit: Unit, code: string) =
  # Code changes that originate from disk (level load, file-watcher reloads)
  # round-trip through here; write_file_if_changed keeps them from bumping
  # the mtime and reload-looping another instance on the same level dir.
  write_file_if_changed(unit.script_ctx.script, code)
  try:
    unit.script_ctx.last_saved_mtime =
      get_last_modification_time(unit.script_ctx.script)
  except OSError:
    discard

proc change_code(self: Worker, unit: Unit, code: Code) =
  debug "code changing", unit = unit.id
  unit.errors.clear
  unit.global_flags -= HIGHLIGHT_ERROR
  if ?unit.script_ctx and unit.script_ctx.running and not ?unit.clone_of:
    unit.collect_garbage

  unit.reset()
  if LOADING_SCRIPT notin state.local_flags and code.nim.strip == "":
    self.interpreter.reset_module(unit.script_ctx.module_name)
    debug "reset module", module = unit.script_ctx.module_name
    unit.script_ctx.running = false
    try:
      remove_file unit.script_ctx.script
    except OSError:
      discard
  elif code.nim.strip != "":
    debug "loading unit", unit_id = unit.id
    if LOADING_SCRIPT notin state.local_flags and not self.retry_failures:
      unit.write_script_file(code.nim)
      if not self.interpreter.is_nil:
        self.load_script_and_dependents(unit)
      else:
        # We load the player before we init the interpreter to get to an
        # interactive state quicker. Otherwise this shouldn't ever be nil.
        assert unit.id == state.player.id
    else:
      self.load_script(unit)

const file_watch_interval = 2.seconds

proc update_files*(self: Worker) =
  if SERVER notin state.local_flags:
    return

  # Detect on-disk deletions before the mtime scans (which silently swallow
  # OSError for missing files and so would leave a deleted unit in state).
  var unit_deletions: seq[Unit]
  var script_clears: seq[Unit]
  for unit in state.units.value:
    if not ?unit.script_ctx:
      continue
    # Skip units whose JSON has never been observed (still initializing) —
    # we can't tell "deleted" from "never existed yet".
    if unit.script_ctx.last_saved_json_mtime != Time.default and
        not file_exists(unit.data_file):
      unit_deletions.add(unit)
      continue
    if unit.script_ctx.script != "" and
        unit.script_ctx.last_saved_mtime != Time.default and
        not file_exists(unit.script_ctx.script):
      script_clears.add(unit)

  for unit in unit_deletions:
    debug "unit data file deleted on disk; removing", unit_id = unit.id
    if unit.parent.is_nil:
      state.units -= unit
    else:
      unit.parent.units -= unit
  if unit_deletions.len > 0:
    save_level(state.config.level_dir)

  for unit in script_clears:
    debug "script file deleted on disk; clearing code", unit_id = unit.id
    # Mark the script as unobserved so a future re-add re-loads it.
    unit.script_ctx.last_saved_mtime = Time.default
    unit.code = Code.init("")

  # Script mtime scan (root-level units only; nested units handled via deps).
  # Use `touch` rather than `=` so the watcher re-runs the script even when
  # the file's mtime changed but its content didn't (e.g. an explicit save
  # to force a re-run). watch_code -> change_code already does reset + reload,
  # mirroring the in-game editor's save path.
  for unit in state.units.value:
    if ?unit.script_ctx and unit.script_ctx.script != "":
      try:
        let mtime = get_last_modification_time(unit.script_ctx.script)
        if mtime != unit.script_ctx.last_saved_mtime:
          let code = read_file(unit.script_ctx.script)
          unit.script_ctx.last_saved_mtime = mtime
          unit.code_value.touch Code.init(code)
      except OSError:
        discard

  # Build root-unit table once for JSON watch and orphan detection
  var root_units: Table[string, Unit]
  for unit in state.units.value:
    root_units[unit.id] = unit

  # JSON watch: reload changed units inline; collect newly-appeared ones to
  # load together as a batch afterward.
  var new_units: seq[tuple[id, json_file: string]]
  for dir in walk_dirs(state.config.data_dir / "*"):
    let unit_id = dir.split_path.tail
    let json_file = dir / unit_id & ".json"
    if not file_exists(json_file):
      continue
    if unit_id in root_units:
      let unit = root_units[unit_id]
      if not (unit of Build or unit of Bot) or not ?unit.script_ctx:
        continue
      if unit.script_ctx.last_saved_json_mtime == Time.default:
        continue
      try:
        let json_mtime = get_last_modification_time(unit.data_file)
        if json_mtime != unit.script_ctx.last_saved_json_mtime:
          let parent = unit.parent
          state.push_flag LOADING_SCRIPT
          if parent.is_nil:
            state.units -= unit
          else:
            parent.units -= unit
          state.pop_flag LOADING_SCRIPT
          load_unit_from_json(unit_id, json_file)
      except OSError:
        discard
    else:
      new_units.add (unit_id, json_file)

  # Load newly-appeared units as one batch: queue each (deferring "symbol not
  # found" failures) under retry_failures, then retry until they all resolve.
  # Cross-script dependencies between simultaneously-added units (e.g. a proto
  # and the spawner that references it) sort themselves out regardless of
  # filesystem order, the same way a full level load does.
  if new_units.len > 0:
    state.push_flag LOADING_SCRIPT
    self.retry_failures = true
    for (unit_id, json_file) in new_units:
      try:
        load_unit_from_json(unit_id, json_file)
      except Exception as e:
        error "Failed to load new unit from JSON", unit_id, error = e
    self.retry_failed_scripts()
    self.retry_failures = false
    state.pop_flag LOADING_SCRIPT
    save_level(state.config.level_dir)

  # Detect orphan scripts (report once)
  for script_path in walk_files(state.config.script_dir / "*.nim"):
    let stem = script_path.split_file.name
    if stem == "players":
      continue
    if stem notin root_units:
      let json_file = state.config.data_dir / stem / stem & ".json"
      if not file_exists(json_file) and
          script_path notin self.orphan_scripts_reported:
        state.err("Orphan script: " & script_path & " (no data file)")
        self.orphan_scripts_reported.incl(script_path)

  self.watch_files_at = get_mono_time() + file_watch_interval

proc watch_code(self: Worker, unit: Unit) =
  unit.code_value.changes:
    if added or touched:
      if change.item.runner == Ed.thread_ctx.id:
        save_level(state.config.level_dir)
        self.change_code(unit, change.item)
        if change.item.nim == "":
          remove_file unit.script_ctx.script
        else:
          unit.write_script_file(change.item.nim)

  unit.eval_value.changes:
    if added or touched and change.item != "":
      unit.eval = ""
      try:
        discard self.eval(unit, change.item)
      except VMQuit as e:
        self.script_error(unit, e)

  let errors_zid = unit.errors.changes:
    if unit.code.owner == Ed.thread_ctx.id:
      if added and change.item.log:
        state.err(
          \"[url=unit://{unit.id}]{change.item.msg} {unit.errors.len}[/url]"
        )
        state.push_flags CONSOLE_VISIBLE

      if removed:
        state.pop_flags CONSOLE_VISIBLE
  unit.errors.bind_lifetime(unit.require_lifetime, errors_zid)

  if unit.script_ctx.is_nil:
    unit.script_ctx =
      ScriptCtx.init(owner = unit, interpreter = self.interpreter)

    unit.script_ctx.script = script_file_for unit
    try:
      unit.script_ctx.last_saved_mtime =
        get_last_modification_time(unit.script_ctx.script)
    except OSError:
      discard
    try:
      unit.script_ctx.last_saved_json_mtime =
        get_last_modification_time(unit.data_file)
    except OSError:
      discard

proc watch_units(
    self: Worker,
    units: EdSeq[Unit],
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
        if SERVER notin state.local_flags and not unit.sync_ready:
          # Narrow partial replica: the unit arrived without its data. One deep
          # fetch pulls its whole ownership closure (containers + subtree); the
          # fills relay to the node ctx, whose deferred scene add completes.
          discard Ed.thread_ctx.fetch(unit.id, deep = true)
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

proc worker_thread(params: (EdContext, GameState)) {.gcsafe.} =
  let (ctx, main_thread_state) = params
  worker_lock.acquire

  var
    listen_address =
      main_thread_state.config.listen_address_override ||
      main_thread_state.config.listen_address
    connect_address =
      main_thread_state.config.connect_address_override ||
      main_thread_state.config.connect_address
    worker_ctx: EdContext

  let is_server = ?listen_address or not ?connect_address
  worker_ctx = EdContext.init(
    id = "work-" & generate_id(),
    chan_size = 500,
    buffer = false,
    listen_address = listen_address,
    label = "worker",
    is_authority = is_server
  )

  Ed.thread_ctx = worker_ctx
  ctx.subscribe(Ed.thread_ctx)

  state = GameState.init_from(main_thread_state)
  state.init_logger

  if is_server:
    state.push_flag SERVER
    state.server_ctx_name = worker_ctx.id

  state.config_value = EdValue[Config](Ed.thread_ctx["config"])
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
      if unit.sync_ready:
        unit.worker_thread_joined(worker)
        worker.watch_code unit
      else:
        # Narrow replica: the unit's data is still arriving (the deep fetch in
        # watch_units pulls it). Join once it lands — drained per loop tick.
        worker.pending_units.add unit

    if removed:
      worker.unmap_unit(unit)

      if ?unit.script_ctx:
        unit.script_ctx.running = false
        unit.script_ctx.callback = nil
        if not (unit of Player) and LOADING_SCRIPT notin state.local_flags and
            not ?unit.clone_of:
          remove_file unit.script_ctx.script
          remove_dir unit.data_dir

      unit.destroy

  let player = state.player

  # add player before interpreter is initialized to get to an interactive
  # state quicker
  if SERVER in state.local_flags:
    state.units.add player
  else:
    state.push_flag(CONNECTING)
    let tmp_path = join_path(state.config.work_dir, "tmp")
    create_dir tmp_path
    state.config_value.value:
      script_dir = tmp_path

  worker.init_interpreter("")
  worker.bridge_to_vm

  worker.mcp_eval_proc = proc(
      code: string, top_level: bool, unit_id: string
  ): tuple[result: string, error: string] {.gcsafe.} =
    try:
      var unit: Unit = state.player
      if unit_id != "":
        unit = nil
        proc find_in(units: EdSeq[Unit]): Unit =
          for u in units.value:
            if u.id == unit_id:
              return u
            let found = find_in(u.units)
            if not found.is_nil:
              return found

        unit = find_in(state.units)
        if unit.is_nil:
          return ("", "Error: unit not found: " & unit_id)
        if unit.script_ctx.is_nil or unit.script_ctx.interpreter.is_nil:
          return ("", "Error: unit has no script context: " & unit_id)
        # Clones share the proto's module — they don't have one of their
        # own. The interpreter.eval below would assert on a missing
        # module, taking the worker thread down. Surface a clean error
        # instead.
        if not unit.clone_of.is_nil:
          return (
            "",
            "Error: unit " & unit_id & " is a clone; eval in clone context " &
              "isn't supported. Try the proto: " & unit.clone_of.id,
          )
      let wrapped =
        if top_level:
          code
        else:
          let indented = code.split_lines.map_it("  " & it).join("\n")
          "(block:\n" & indented & "\n)"
      (worker.eval(unit, wrapped).get(""), "")
    except VMQuit as e:
      (
        "",
        if e.location.len > 0:
          "Error at " & e.location & ": " & e.msg
        else:
          "Error: " & e.msg,
      )
    except CatchableError as e:
      ("", "Error: " & e.msg)

  worker.mcp_update_files_proc = proc() {.gcsafe.} =
    worker.update_files()

  let load_level = proc() =
    var level_dir = state.config.level_dir
    player.script_ctx.interpreter = worker.interpreter
    worker.load_script_and_dependents(player)

    worker.load_level(level_dir)
    state.level_name = state.config.world & "/" & state.config.level
    state.config_value.changes:
      if added:
        if change.item.level_dir != level_dir:
          let full_reset = RESETTING_VM in state.local_flags
          if level_dir != "":
            save_level(level_dir, save_all = full_reset)
          worker.unload_level()
          if full_reset:
            worker.init_interpreter("")
            worker.bridge_to_vm
            player.script_ctx.interpreter = worker.interpreter
            worker.initial_load_done = false
            worker.load_script_and_dependents(player)
          level_dir = change.item.level_dir
          if level_dir != "":
            worker.load_level(level_dir)

  if SERVER in state.local_flags:
    load_level()
  else:
    var timeout_at = get_mono_time() + 30.seconds
    var connected = false
    while not connected and get_mono_time() < timeout_at:
      try:
        Ed.thread_ctx.subscribe(
          # Partial replica: the unit directory plus (server-pushed) each
          # unit's ownership closure — see OWNS_MEMBERS on root_units. Our own
          # writes still flow up (the reverse direction stays full).
          connect_address,
          partial = true,
          # deep stays default-false for now: a stress test of the narrow path
          # (placeholders + materialize-on-access). Flip to deep = true if it
          # doesn't hold up — that pushes unit closures so units arrive
          # render-ready.
          fetch = ["root_units"],
        )
        connected = true
        # Get the remote server's context ID from subscribers
        for sub in Ed.thread_ctx.subscribers:
          if sub.kind == Remote:
            state.server_ctx_name = sub.ctx_id
            break
        info "connected to server"
      except ConnectionError:
        discard

    state.pop_flag(CONNECTING)
    state.units.add player
    player.script_ctx.interpreter = worker.interpreter
    if not connected:
      state.err \"Unable to connect to server at {connect_address}"
      state.config_value.value:
        connect_address = ""
      state.push_flag SERVER
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
  sign.global_flags -= VISIBLE
  sign.local_flags += HIDE

  var running = true
  if NEEDS_RESTART in state.local_flags:
    running = false

  state.local_flags.changes:
    if QUITTING.added:
      save_level(state.config.level_dir)
      # In test mode, don't pop the flag - let the main thread's force_quit_at
      # timeout handle it. This ensures test_exit_code has time to propagate.
      if TEST_MODE notin state.local_flags:
        state.pop_flag QUITTING
      running = false
    elif NEEDS_RESTART.added:
      running = false

  state.config_value.changes:
    if added:
      let uc = state.config.build_user_config
      save_user_config(uc)

    if state.config.player_color != change.item.player_color:
      player.color = state.config.player_color

  const max_time = (1.0 / 30.0).seconds
  const min_time = (1.0 / 60.0).seconds
  const auto_save_interval = 30.seconds
  const backup_interval = 15.minutes
  const test_timeout = 5.minutes
  const stats_log_interval = 5.seconds
  const asap_flush_interval = 2.seconds
  var save_at = get_mono_time() + auto_save_interval
  var backup_at = MonoTime.low
  var test_started_at = MonoTime.high
  var last_stats_log = MonoTime.low
  var last_asap_flush = MonoTime.low
  var was_in_asap = false
  var last_snapshots_flushed = 0
  var last_deltas_flushed = 0
  var tick_count = 0
  var last_tick_count = 0
  var max_tick_time = Duration.default
  # Voxel paging (partial clients): request chunks near the player, release
  # far ones. No-op on the server / single player.
  var pager = ChunkPager.init

  try:
    while running:
      let frame_start = get_mono_time()
      let timeout = frame_start + max_time
      let wait_until = frame_start + min_time
      inc tick_count

      if worker.pending_units.len > 0:
        var still_pending: seq[Unit]
        for unit in worker.pending_units:
          if unit.destroyed:
            continue
          if unit.sync_ready:
            unit.worker_thread_joined(worker)
            worker.watch_code unit
          else:
            still_pending.add unit
        worker.pending_units = still_pending

      for ctx_name in Ed.thread_ctx.unsubscribed:
        var i = 0
        while i < state.units.len:
          let unit = state.units[i]
          # AGENT units encode their owning context name in their id
          # (`player-{ctx_name}`, `mcp_bot-{ctx_name}`, ...). When the
          # context unsubscribes, drop the corresponding agents.
          if AGENT in unit.global_flags and ctx_name in unit.id:
            state.units.del i
          else:
            i += 1

        if SERVER notin state.local_flags:
          state.push_flag(NEEDS_RESTART)
          break

      var to_process: seq[Unit]
      state.units.value.walk_tree proc(unit: Unit) =
        if unit.code.runner == Ed.thread_ctx.id and ?unit.script_ctx:
          if unit.script_ctx.running:
            unit.global_flags += SCRIPT_RUNNING
          else:
            unit.global_flags -= SCRIPT_RUNNING
        to_process.add unit
      to_process.shuffle

      # Check if any unit is in ASAP mode - if so, skip voxel_tasks check
      # because periodic paste will cause many tasks to queue up
      var any_asap = false
      for unit in to_process:
        if unit of Build and ASAP_MODE in Build(unit).global_flags:
          any_asap = true
          break

      # Reset flush timer when entering ASAP mode
      if any_asap and not was_in_asap:
        last_asap_flush = frame_start
      was_in_asap = any_asap

      while Ed.thread_ctx.pressure < 0.9 and to_process.len > 0 and
          (any_asap or state.voxel_tasks <= 10) and get_mono_time() < timeout:
        let units = to_process
        to_process = @[]
        for unit in units:
          if READY in unit.global_flags:
            if worker.advance_unit(unit, timeout):
              to_process.add(unit)

      # Flush pending changes for all Builds
      let asap_interval_elapsed =
        frame_start > last_asap_flush + asap_flush_interval
      # Only flush ASAP builds if interval elapsed AND voxel_tasks is low enough
      let can_flush_asap = asap_interval_elapsed and state.voxel_tasks <= 10
      var did_flush_asap = false
      state.units.value.walk_tree proc(unit: Unit) =
        if unit of Build and ?Build(unit).voxels:
          let build = Build(unit)
          let in_asap = ASAP_MODE in build.global_flags
          # Flush if not in ASAP mode, or if in ASAP mode and we can flush
          let should_flush = not in_asap or can_flush_asap
          if should_flush:
            if build.voxels.pending_chunks.len > 0:
              build.voxels.flush_dirty_chunks()
              if in_asap:
                did_flush_asap = true
            if build.voxels.pending_edits.len > 0:
              build.voxels.flush_dirty_edits()
      # Only reset timer if we actually flushed during ASAP mode
      if did_flush_asap:
        last_asap_flush = frame_start

      pager.tick # page voxel chunks in/out around the player (clients)

      Ed.thread_ctx.tick
      run_deferred()

      # Update network stats for main thread
      if ?Ed.thread_ctx.reactor:
        state.net_connections = Ed.thread_ctx.reactor.connections.len
      else:
        state.net_connections = 0

      # Log stats periodically
      if frame_start > last_stats_log + stats_log_interval:
        var total_snapshots = 0
        var total_deltas = 0
        state.units.value.walk_tree proc(unit: Unit) =
          if unit of Build and ?Build(unit).voxels:
            total_snapshots += Build(unit).voxels.snapshots_flushed
            total_deltas += Build(unit).voxels.deltas_flushed

        let snapshots_this_period = total_snapshots - last_snapshots_flushed
        let deltas_this_period = total_deltas - last_deltas_flushed
        let ticks_delta = tick_count - last_tick_count
        let ticks_per_sec =
          ticks_delta.float / stats_log_interval.in_seconds.float

        if snapshots_this_period > 0 or deltas_this_period > 0 or ticks_delta > 0:
          info "worker stats",
            ticks_per_sec = ticks_per_sec.int,
            max_tick_ms = max_tick_time.in_milliseconds,
            snapshots = total_snapshots,
            snapshots_delta = snapshots_this_period,
            deltas = total_deltas,
            deltas_delta = deltas_this_period
        last_stats_log = frame_start
        last_snapshots_flushed = total_snapshots
        last_deltas_flushed = total_deltas
        last_tick_count = tick_count
        max_tick_time = Duration.default

      # In test mode, exit when all scripts have finished
      if TEST_MODE in state.local_flags:
        if test_started_at == MonoTime.high:
          test_started_at = get_mono_time()
          notice "test mode started"

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
          notice "test mode running",
            elapsed = elapsed, scripts = running_scripts

        if not any_running:
          let exit_code =
            if state.test_exit_code < 0: 0 else: state.test_exit_code
          notice "test mode finished", exit_code = exit_code, elapsed = elapsed
          state.test_exit_code = exit_code
          state.push_flag QUITTING
        elif elapsed > test_timeout:
          notice "test mode timeout",
            elapsed = elapsed, scripts = running_scripts
          state.test_exit_code = 1
          state.push_flag QUITTING

      inc state.frame_count

      let now = get_mono_time()

      if now > save_at:
        save_level(state.config.level_dir)
        Ed.thread_ctx.tick_keepalives()
        save_at = now + auto_save_interval

      if now > backup_at and TEST_MODE notin state.local_flags:
        backup_level(state.config.level_dir)
        Ed.thread_ctx.tick_keepalives()
        backup_at = now + backup_interval

      if now > worker.watch_files_at:
        worker.update_files()

      # Track max tick time for debugging
      let tick_time = get_mono_time() - frame_start
      if tick_time > max_tick_time:
        max_tick_time = tick_time

      if now < wait_until:
        sleep int((wait_until - get_mono_time()).in_milliseconds)
  except VMQuit as e:
    error "Unhandled script error in worker thread",
      kind = $e.type, msg = e.msg, stacktrace = e.get_stack_trace
    state.err(e.msg)
  except Exception as e:
    error "Unhandled worker thread exception",
      kind = $e.type, msg = e.msg, stacktrace = e.get_stack_trace

    # Re-raise to crash properly instead of restarting
    raise e
    # state.push_flag(NEEDS_RESTART)

  try:
    if NEEDS_RESTART in state.local_flags:
      if ?listen_address:
        private_access Reactor
        Ed.thread_ctx.reactor.socket.close
      state.pop_flag NEEDS_RESTART

    Ed.thread_ctx.tick
  except Exception:
    discard

proc launch_worker*(
    ctx: EdContext, state: GameState
): system.Thread[tuple[ctx: EdContext, state: GameState]] =
  worker_lock.acquire
  result.create_thread(worker_thread, (ctx, state))
  work_done.wait(worker_lock)
  worker_lock.release
