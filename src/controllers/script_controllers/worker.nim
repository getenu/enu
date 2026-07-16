import std/[locks, os, random, net, json, jsonutils, strutils]
import std/times except seconds, minutes
from pkg/netty import Reactor
import core, models, models/serializers, libs/[interpreters, eval]
import ./[vars, host_bridge, scripting]

var
  worker_lock: locks.Lock
  work_done: locks.Cond

worker_lock.init_lock
work_done.init_cond

proc handle_catchable_error(self: Worker, thing: Thing, e: ref Exception) =
  ## Convert host-side exception to VMQuit and display in console.
  ## Accepts Defect as well as CatchableError so VM-level bugs (e.g.
  ## IndexDefect from corrupted register frames after module reset) don't
  ## crash the worker thread.
  let ctx = thing.script_ctx
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
  # Add error to thing.errors for console display (similar to error_hook)
  thing.errors.add (e.msg, info, loc, false)
  if ?ctx:
    ctx.exit_code = error_code
    ctx.running = false
  let vm_error =
    (ref VMQuit)(info: info, kind: UNKNOWN, msg: e.msg, location: loc)
  if ?ctx:
    self.interpreter.reset_module(ctx.module_name)
    self.module_names.excl ctx.module_name
  self.script_error(thing, vm_error)

proc advance_thing(self: Worker, thing: Thing, timeout: MonoTime): bool =
  let ctx = thing.script_ctx
  if ?ctx and ctx.running:
    if ASAP_MODE notin thing.global_flags:
      thing.current_line = ctx.current_line.line.int
    if thing of Build:
      let thing = Build(thing)
      thing.update_auto_ramp()
      thing.voxels_remaining_this_frame += thing.voxels_per_frame
    try:
      assert self.active_thing.is_nil
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
        task_state in {TaskStates.DONE, NEXT_TASK}
      ):
        ctx.timer = MonoTime.high
        ctx.action_running = false
        self.active_thing = thing
        ctx.fuel = script_fuel
        ctx.running = ctx.resume()
        if not ctx.running:
          if thing of Build:
            Build(thing).end_asap()
          if not ?thing.clone_of:
            thing.collect_garbage
            thing.ensure_visible
            thing.current_line = 0

        result = ctx.running and task_state == NEXT_TASK
      elif now >= ctx.timer:
        ctx.timer = now + advance_step
        ctx.saved_callback = ctx.callback
        ctx.callback = nil
        self.active_thing = thing
        ctx.fuel = script_fuel
        discard ctx.resume()
    except VMQuit as e:
      self.interpreter.reset_module(thing.script_ctx.module_name)
      self.module_names.excl thing.script_ctx.module_name
      self.script_error(thing, e)
    except CatchableError as e:
      self.handle_catchable_error(thing, e)
    except Defect as e:
      # Bytecode-level defects (e.g. IndexDefect inside vm.nim from a
      # corrupted register frame after module reset) are bugs in the VM/script
      # path, not the host. Treat them as script errors so a single bad script
      # doesn't take down the worker thread.
      self.handle_catchable_error(thing, e)
    finally:
      self.active_thing = nil

proc load_thing_from_json(thing_id, json_file: string) =
  let opts = JOptions(allow_missing_keys: true)
  let data_json = read_file(json_file).parse_json
  var new_thing: Thing
  if thing_id.starts_with("bot_"):
    new_thing = data_json.json_to(Bot, opts)
  elif thing_id.starts_with("build_"):
    new_thing = data_json.json_to(Build, opts)
  else:
    error "Unknown thing type for new JSON file", thing_id
    return
  new_thing.global_flags += SCRIPT_INITIALIZING
  dont_join = true
  state.things.add(new_thing)
  load_things(new_thing, @[])
  dont_join = false
  if new_thing of Build:
    Build(new_thing).reset_bounds
    Build(new_thing).restore_edits
  if ?new_thing.script_ctx:
    new_thing.script_ctx.last_saved_json_mtime =
      get_last_modification_time(json_file)
    if file_exists(new_thing.script_ctx.script):
      new_thing.code = Code.init(read_file(new_thing.script_ctx.script))
    else:
      new_thing.global_flags -= SCRIPT_INITIALIZING
      # A scripted build renders its restored edits when its code loads
      # (change_code -> reset, then end_asap when the script finishes). A
      # build with no script never gets that pass, so do it here: reset()
      # restores+draws into the ASAP buffer, end_asap() flushes it to a mesh.
      if new_thing of Build:
        Build(new_thing).reset()
        Build(new_thing).end_asap()

proc write_script_file(thing: Thing, code: string) =
  # Code changes that originate from disk (level load, file-watcher reloads)
  # round-trip through here; write_file_if_changed keeps them from bumping
  # the mtime and reload-looping another instance on the same level dir.
  write_file_if_changed(thing.script_ctx.script, code)
  try:
    thing.script_ctx.last_saved_mtime =
      get_last_modification_time(thing.script_ctx.script)
  except OSError:
    discard

proc change_code(self: Worker, thing: Thing, code: Code) =
  debug "code changing", thing = thing.id
  thing.errors.clear
  thing.global_flags -= HIGHLIGHT_ERROR
  if ?thing.script_ctx and thing.script_ctx.running and not ?thing.clone_of:
    thing.collect_garbage

  thing.reset()
  if LOADING_SCRIPT notin state.local_flags and code.nim.strip == "":
    self.interpreter.reset_module(thing.script_ctx.module_name)
    self.module_names.excl thing.script_ctx.module_name
    debug "reset module", module = thing.script_ctx.module_name
    thing.script_ctx.running = false
    try:
      remove_file thing.script_ctx.script
    except OSError:
      discard
  elif code.nim.strip != "":
    debug "loading thing", thing_id = thing.id
    # A live run (the editor or a file-watch save, never a level/reload which
    # sets LOADING_SCRIPT) arms the auto-speed ramp so the build visibly draws
    # itself. Loads stay in ASAP and just appear.
    if thing of Build and LOADING_SCRIPT notin state.local_flags and
        Build(thing).speed == AUTO:
      Build(thing).arm_auto_ramp()
    if LOADING_SCRIPT notin state.local_flags and not self.retry_failures:
      thing.write_script_file(code.nim)
      if not self.interpreter.is_nil:
        self.load_script_and_dependents(thing)
      else:
        # We load the player before we init the interpreter to get to an
        # interactive state quicker. Otherwise this shouldn't ever be nil.
        assert thing.id == state.player.id
    else:
      self.load_script(thing)

const file_watch_interval = 2.seconds

proc update_files*(self: Worker) =
  if SERVER notin state.local_flags:
    return

  # Mid-reload there is no level: switch_world(0) writes level_dir = "" then
  # back, and unload_level has already emptied state.things. Scanning now would
  # make every on-disk thing look newly added and batch-load the whole level
  # into a VM that hasn't run initialize_state yet.
  if state.config.level_dir == "" or RESETTING_VM in state.local_flags or
      LOADING_LEVEL in state.global_flags:
    return

  # Detect on-disk deletions before the mtime scans (which silently swallow
  # OSError for missing files and so would leave a deleted thing in state).
  var thing_deletions: seq[Thing]
  var script_clears: seq[Thing]
  for thing in state.things.value:
    if not ?thing.script_ctx:
      continue
    # Skip things whose JSON has never been observed (still initializing) —
    # we can't tell "deleted" from "never existed yet".
    if thing.script_ctx.last_saved_json_mtime != Time.default and
        not file_exists(thing.data_file):
      thing_deletions.add(thing)
      continue
    if thing.script_ctx.script != "" and
        thing.script_ctx.last_saved_mtime != Time.default and
        not file_exists(thing.script_ctx.script):
      script_clears.add(thing)

  if thing_deletions.len > 0 and state.config.data_dir == "":
    # A blank data_dir means every thing's data_file resolves relative and
    # looks missing; deleting the whole level over that would be a massacre.
    warn "skipping thing deletion scan: config has no data_dir"
    thing_deletions = @[]
  for thing in thing_deletions:
    debug "thing data file deleted on disk; removing",
      thing_id = thing.id, data_file = thing.data_file
    if thing.parent.is_nil:
      state.things -= thing
    else:
      thing.parent.things -= thing
  if thing_deletions.len > 0:
    save_level(state.config.level_dir)

  for thing in script_clears:
    debug "script file deleted on disk; clearing code", thing_id = thing.id
    # Mark the script as unobserved so a future re-add re-loads it.
    thing.script_ctx.last_saved_mtime = Time.default
    thing.code = Code.init("")

  # Script mtime scan (root-level things only; nested things handled via deps).
  # Use `touch` rather than `=` so the watcher re-runs the script even when
  # the file's mtime changed but its content didn't (e.g. an explicit save
  # to force a re-run). watch_code -> change_code already does reset + reload,
  # mirroring the in-game editor's save path.
  for thing in state.things.value:
    if ?thing.script_ctx and thing.script_ctx.script != "":
      try:
        let mtime = get_last_modification_time(thing.script_ctx.script)
        if mtime != thing.script_ctx.last_saved_mtime:
          let code = read_file(thing.script_ctx.script)
          thing.script_ctx.last_saved_mtime = mtime
          thing.code_value.touch Code.init(code)
      except OSError:
        discard

  # Table of every loaded thing (whole tree, not just top level) for the JSON
  # watch + orphan detection. A thing adopted onto another lives nested in memory
  # but its data stays at the flat top-level path, so it'd otherwise look "new"
  # to the walk_dirs scan below and get reconstructed. Walking the tree keeps it
  # recognized as already-loaded.
  var loaded_things: Table[string, Thing]
  state.things.value.walk_tree proc(thing: Thing) {.gcsafe.} =
    loaded_things[thing.id] = thing

  # JSON watch: reload changed things inline; collect newly-appeared ones to
  # load together as a batch afterward.
  var new_things: seq[tuple[id, json_file: string]]
  for dir in walk_dirs(state.config.data_dir / "*"):
    let thing_id = dir.split_path.tail
    let json_file = dir / thing_id & ".json"
    if not file_exists(json_file):
      continue
    if thing_id in loaded_things:
      let thing = loaded_things[thing_id]
      if not (thing of Build or thing of Bot) or not ?thing.script_ctx:
        continue
      if thing.script_ctx.last_saved_json_mtime == Time.default:
        continue
      try:
        let json_mtime = get_last_modification_time(thing.data_file)
        if json_mtime != thing.script_ctx.last_saved_json_mtime:
          debug "thing json changed on disk; reloading",
            thing_id = thing.id, json_mtime
          let parent = thing.parent
          state.push_flag LOADING_SCRIPT
          if parent.is_nil:
            state.things -= thing
          else:
            parent.things -= thing
          state.pop_flag LOADING_SCRIPT
          load_thing_from_json(thing_id, json_file)
      except OSError:
        discard
    else:
      new_things.add (thing_id, json_file)

  # Load newly-appeared things as one batch: queue each (deferring "symbol not
  # found" failures) under retry_failures, then retry until they all resolve.
  # Cross-script dependencies between simultaneously-added things (e.g. a proto
  # and the spawner that references it) sort themselves out regardless of
  # filesystem order, the same way a full level load does.
  if new_things.len > 0:
    state.push_flag LOADING_SCRIPT
    self.retry_failures = true
    for (thing_id, json_file) in new_things:
      try:
        load_thing_from_json(thing_id, json_file)
      except Exception as e:
        error "Failed to load new thing from JSON", thing_id, error = e
    self.retry_failed_scripts()
    self.retry_failures = false
    state.pop_flag LOADING_SCRIPT
    save_level(state.config.level_dir)

  # Detect orphan scripts (report once)
  for script_path in walk_files(state.config.script_dir / "*.nim"):
    let stem = script_path.split_file.name
    if stem == "players":
      continue
    if stem notin loaded_things:
      let json_file = state.config.data_dir / stem / stem & ".json"
      if not file_exists(json_file) and
          script_path notin self.orphan_scripts_reported:
        # Log only — an orphan is a developer-side curiosity, not something
        # the player should see in the console.
        warn "orphan script (no data file)", script_path
        self.orphan_scripts_reported.incl(script_path)

  self.watch_files_at = get_mono_time() + file_watch_interval

proc watch_code(self: Worker, thing: Thing) =
  thing.code_value.changes:
    if added or touched:
      if change.item.runner == Ed.thread_ctx.id:
        if not level_loading:
          # the loader assigns every unit's code; saving the level it is
          # mid-loading re-encoded everything back to disk for nothing
          save_level(state.config.level_dir)
        self.change_code(thing, change.item)
        if change.item.nim == "":
          remove_file thing.script_ctx.script
        else:
          thing.write_script_file(change.item.nim)

  thing.eval_value.changes:
    if added or touched and change.item != "":
      thing.eval = ""
      try:
        discard self.eval(thing, change.item)
      except VMQuit as e:
        self.script_error(thing, e)

  let errors_zid = thing.errors.changes:
    if thing.code.owner == Ed.thread_ctx.id:
      if added and change.item.log:
        state.err(
          \"[url=thing://{thing.id}]{change.item.msg} {thing.errors.len}[/url]"
        )
        if state.config.auto_show_console:
          state.push_flags CONSOLE_VISIBLE

      if removed and state.config.auto_show_console:
        state.pop_flags CONSOLE_VISIBLE
  thing.errors.bind_lifetime(thing.require_lifetime, errors_zid)

  if thing.script_ctx.is_nil:
    thing.script_ctx =
      ScriptCtx.init(owner = thing, interpreter = self.interpreter)

    thing.script_ctx.script = script_file_for thing
    try:
      thing.script_ctx.last_saved_mtime =
        get_last_modification_time(thing.script_ctx.script)
    except OSError:
      discard
    try:
      thing.script_ctx.last_saved_json_mtime =
        get_last_modification_time(thing.data_file)
    except OSError:
      discard

proc finish_test_run(self: Worker, timed_out: bool) =
  ## End the test run: fold the tallies scripts reported into the process
  ## exit code and print one summary for the whole run. Idempotent — the
  ## worker keeps looping until QUITTING propagates, so guard against
  ## reporting twice.
  if QUITTING in state.local_flags:
    return
  let exit_code = self.test_fail_count + self.test_error_count
  notice "test run complete",
    scripts = self.test_report_count,
    tests = self.test_run_count,
    passed = self.test_pass_count,
    failed = self.test_fail_count,
    errors = self.test_error_count,
    timed_out = timed_out,
    exit_code = exit_code
  state.test_exit_code = exit_code
  state.push_flag QUITTING

proc watch_things(
    self: Worker,
    things: EdSeq[Thing],
    parent: Thing,
    body: proc(thing: Thing, change: Change[Thing], added: bool, removed: bool) {.
      gcsafe
    .},
) {.gcsafe.} =
  things.track proc(changes: seq[Change[Thing]]) {.gcsafe.} =
    for change in changes:
      let thing = change.item
      let added = Added in change.changes
      let removed = Removed in change.changes
      body(thing, change, added, removed)
      if added:
        # FIXME: this is being set for the main thread in node_controller
        thing.fix_parents(parent)
        thing.frame_created = state.frame_count
        if SERVER notin state.local_flags and not thing.sync_ready:
          # Narrow partial replica: the thing arrived without its data. One deep
          # fetch pulls its whole ownership closure (containers + subtree); the
          # fills relay to the node ctx, whose deferred scene add completes.
          discard Ed.thread_ctx.fetch(thing.id, deep = true)
        # A TRANSFERRING add is a reparent relink (adopt/release), not a new
        # thing: its collision and child-collection watchers are already
        # registered, and re-adding them would run every downstream join and
        # teardown once per accumulated subscription (growing with each hop).
        if TRANSFERRING notin thing.global_flags:
          thing.collisions.track proc(changes: seq[Change[(string, Vector3)]]) =
            # script_ctx is nil for a thing that never finished joining (a narrow
            # replica's deferred join, destroyed before its fetch completed —
            # e.g. an agent bot churned during a reload). The CLOSED this
            # watcher gets from that destroy must not deref it.
            if ?thing.script_ctx:
              thing.script_ctx.timer = get_mono_time()
          self.watch_things(thing.things, thing, body)

template for_all_things(self: Worker, body: untyped) {.dirty.} =
  self.watch_things state.things,
    parent = nil,
    proc(
        thing: Thing, change: Change[Thing], added: bool, removed: bool
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
    # Non-blocking sends. A blocking send (buffer = false) freezes the whole
    # worker thread mid-flush when main's inbox is full -- the level-change
    # deadlock. With buffer = true the worker overflows into its per-subscriber
    # buffer instead; the existing `pressure < 0.9` advance gate keeps that
    # overflow bounded by declining to produce while main is behind. See the
    # ed channel_bench harness.
    buffer = true,
    listen_address = listen_address,
    label = "worker",
    is_authority = is_server,
    # Partial clients page voxel data on demand; cap resident body memory so
    # the evictor reclaims dormant chunks/residue (LRU). A low see-it-work
    # value for now — the server (full authority) holds everything (Unbounded).
    mem_limit = (if is_server: Unbounded else: 16 * 1024 * 1024),
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

  worker.for_all_things:
    # A thing appearing or leaving counts as test-mode activity: it resets the
    # quiescence timer so the run doesn't declare itself finished while scripts
    # are still loading or being reaped.
    if TEST_MODE in state.local_flags:
      worker.test_last_activity = get_mono_time()
    if added:
      if TRANSFERRING in thing.global_flags:
        # Relink (adopt/release): the thing is already joined and its script is
        # running. Re-adding it to a new collection must not re-join or re-watch.
        discard
      elif thing.sync_ready:
        thing.worker_thread_joined(worker)
        worker.watch_code thing
      else:
        # Narrow replica: the thing's data is still arriving (the deep fetch in
        # watch_things pulls it). Join once it lands — drained per loop tick.
        worker.pending_things.add thing

    if removed:
      if TRANSFERRING in thing.global_flags:
        # Moving between collections, not leaving the level: keep the thing, its
        # script mapping, and its on-disk script/data intact.
        discard
      else:
        worker.unmap_thing(thing)

        if ?thing.script_ctx:
          thing.script_ctx.running = false
          thing.script_ctx.callback = nil
          if not (thing of Player) and LOADING_SCRIPT notin state.local_flags and
              not ?thing.clone_of:
            remove_file thing.script_ctx.script
            remove_dir thing.data_dir

        thing.destroy

  let player = state.player

  # add player before interpreter is initialized to get to an interactive
  # state quicker
  if SERVER in state.local_flags:
    state.things.add player
  else:
    state.push_flag(CONNECTING)
    let tmp_path = join_path(state.config.work_dir, "tmp")
    create_dir tmp_path
    state.config_value.value:
      script_dir = tmp_path

  worker.init_interpreter("")
  worker.bridge_to_vm

  worker.eval_proc = proc(
      code: string, top_level: bool, thing_id: string
  ): tuple[result: string, error: string] {.gcsafe.} =
    try:
      var thing: Thing = state.player
      if thing_id != "":
        thing = nil
        proc find_in(things: EdSeq[Thing]): Thing =
          for u in things.value:
            if u.id == thing_id:
              return u
            let found = find_in(u.things)
            if not found.is_nil:
              return found

        thing = find_in(state.things)
        if thing.is_nil:
          return ("", "Error: thing not found: " & thing_id)
        if thing.destroyed:
          # a reload can briefly leave the outgoing instance findable; its
          # Ed fields are torn down and any accessor would crash the worker
          return ("", "Error: thing is reloading, try again: " & thing_id)
        if thing.script_ctx.is_nil or thing.script_ctx.interpreter.is_nil:
          return ("", "Error: thing has no script context: " & thing_id)
        # Clones share the proto's module — they don't have one of their
        # own. The interpreter.eval below would assert on a missing
        # module, taking the worker thread down. Surface a clean error
        # instead.
        if not thing.clone_of.is_nil:
          return (
            "",
            "Error: thing " & thing_id & " is a clone; eval in clone context " &
              "isn't supported. Try the proto: " & thing.clone_of.id,
          )
      let wrapped =
        if top_level:
          code
        else:
          let indented = code.split_lines.map_it("  " & it).join("\n")
          "(block:\n" & indented & "\n)"
      (worker.eval(thing, wrapped).get(""), "")
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

  worker.update_files_proc = proc() {.gcsafe.} =
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
            worker.load_script_and_dependents(player)
            # The fresh VM has no `player` global until initialize_state runs,
            # and load_level (which normally runs it) may not happen until a
            # later change event. Anything that loads a thing script in that
            # window hits a nil player at script top level.
            worker.run_state_initializers()
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
          # Partial replica: the thing directory plus (server-pushed) each
          # thing's ownership closure — see OWNS_MEMBERS on root_things. Our own
          # writes still flow up (the reverse direction stays full).
          connect_address,
          # Non-blocking partial: placeholders fill on later ticks, never
          # stalling the frame loop waiting on the network.
          mode = PARTIAL_ASYNC,
          # deep stays default-false for now: a stress test of the narrow path
          # (placeholders + materialize-on-access). Flip to deep = true if it
          # doesn't hold up — that pushes thing closures so things arrive
          # render-ready.
          fetch = ["root_things"],
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
    state.things.add player
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

  state.player.things += sign
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
  # Stop flushing voxels into the channel once it's this full, leaving the rest
  # to coalesce in pending_chunks for a later frame. Matches the advance gate so
  # production and flushing back off together. See ed's channel_bench harness.
  const flush_pressure_gate = 0.9
  const auto_save_interval = 30.seconds
  const backup_interval = 15.minutes
  const test_timeout = 5.minutes
  # How long the run must stay idle (nothing running, retrying, or being
  # added/removed) before we call it done. Long enough to bridge the gaps
  # while scripts load and finished test things are reaped, short enough to
  # keep the suite quick.
  const test_quiesce_grace = initDuration(milliseconds = 750)
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

  try:
    while running:
      let frame_start = get_mono_time()
      let timeout = frame_start + max_time
      let wait_until = frame_start + min_time
      inc tick_count

      if worker.pending_things.len > 0:
        var still_pending: seq[Thing]
        for thing in worker.pending_things:
          if thing.destroyed:
            continue
          if thing.sync_ready:
            thing.worker_thread_joined(worker)
            worker.watch_code thing
          else:
            still_pending.add thing
        worker.pending_things = still_pending

      for ctx_name in Ed.thread_ctx.drain_unsubscribed:
        var i = 0
        while i < state.things.len:
          let thing = state.things[i]
          # EPHEMERAL things carry the ctx that created them in `owner_ctx`.
          # When that context unsubscribes, drop the corresponding agents.
          if EPHEMERAL in thing.global_flags and thing.owner_ctx == ctx_name:
            debug "reaping agent thing on ctx unsubscribe",
              thing_id = thing.id, ctx_name
            state.things.del i
          else:
            i += 1

        if SERVER notin state.local_flags:
          state.push_flag(NEEDS_RESTART)
          break

      var to_process: seq[Thing]
      state.things.value.walk_tree proc(thing: Thing) =
        if thing.code.runner == Ed.thread_ctx.id and ?thing.script_ctx:
          if thing.script_ctx.running:
            thing.global_flags += SCRIPT_RUNNING
          else:
            thing.global_flags -= SCRIPT_RUNNING
        to_process.add thing
      to_process.shuffle

      # Check if any thing is in ASAP mode - if so, skip voxel_tasks check
      # because periodic paste will cause many tasks to queue up
      var any_asap = false
      for thing in to_process:
        if thing of Build and ASAP_MODE in Build(thing).global_flags:
          any_asap = true
          break

      # Reset flush timer when entering ASAP mode
      if any_asap and not was_in_asap:
        last_asap_flush = frame_start
      was_in_asap = any_asap

      while Ed.thread_ctx.pressure < 0.9 and to_process.len > 0 and
          (any_asap or state.voxel_tasks <= 10) and get_mono_time() < timeout:
        let things = to_process
        to_process = @[]
        for thing in things:
          if READY in thing.global_flags:
            if worker.advance_thing(thing, timeout):
              to_process.add(thing)

      # Flush pending changes for all Builds
      let asap_interval_elapsed =
        frame_start > last_asap_flush + asap_flush_interval
      # Only flush ASAP builds if interval elapsed AND voxel_tasks is low enough
      let can_flush_asap = asap_interval_elapsed and state.voxel_tasks <= 10
      var did_flush_asap = false
      state.things.value.walk_tree proc(thing: Thing) =
        if thing of Build and ?Build(thing).voxels:
          let build = Build(thing)
          let in_asap = ASAP_MODE in build.global_flags
          # Flush if not in ASAP mode, or if in ASAP mode and we can flush
          let should_flush = not in_asap or can_flush_asap
          if should_flush:
            if build.voxels.pending_chunks.len > 0 or
                build.voxels.pending_snapshots.len > 0:
              # Flush chunk-by-chunk, backing off once the channel hits the gate
              # (the rest stay in pending_chunks and coalesce next frame).
              for _ in build.voxels.flush_dirty_chunks():
                if in_asap:
                  did_flush_asap = true
                if Ed.thread_ctx.pressure >= flush_pressure_gate:
                  break
            if build.voxels.pending_edits.len > 0:
              build.voxels.flush_dirty_edits()
      # Only reset timer if we actually flushed during ASAP mode
      if did_flush_asap:
        last_asap_flush = frame_start

      Ed.thread_ctx.tick
      run_deferred()

      # Update network stats for main thread
      if ?Ed.thread_ctx.reactor:
        state.net_connections = Ed.thread_ctx.reactor.connections.len
      else:
        state.net_connections = 0
      # Surface the worker ctx's resident body bytes (the evictor's pool) to
      # the main-thread stats screen.
      state.ed_mem = Ed.thread_ctx.used_bytes

      # Log stats periodically
      if frame_start > last_stats_log + stats_log_interval:
        var total_snapshots = 0
        var total_deltas = 0
        state.things.value.walk_tree proc(thing: Thing) =
          if thing of Build and ?Build(thing).voxels:
            total_snapshots += Build(thing).voxels.snapshots_flushed
            total_deltas += Build(thing).voxels.deltas_flushed

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
            deltas_delta = deltas_this_period,
            ed_objects = Ed.thread_ctx.len
        if get_env("ENU_VOXEL_MEM_LOG") != "":
          # Resident voxel memory sampling — worker-side counterpart of the
          # VOXMEM log in game.nim.
          let s = voxel_mem_stats(state.things)
          info "VOXMEM worker",
            occupied_kb = get_occupied_mem() div 1024,
            builds = s.builds,
            lv_chunks = s.lv_chunks,
            lv_voxels = s.lv_voxels,
            packed = s.packed,
            edit_chunks = s.edit_chunks,
            edit_voxels = s.edit_voxels

        last_stats_log = frame_start
        last_snapshots_flushed = total_snapshots
        last_deltas_flushed = total_deltas
        last_tick_count = tick_count
        max_tick_time = Duration.default

      # In test mode, finish once the run goes quiet: no script running, no
      # script queued for retry, and nothing added/removed for a grace window.
      # We deliberately do NOT treat "state.things has no running scripts" as
      # done on its own — scripts run and report during load (before this loop
      # even starts), and the ed sync layer then removes the finished test
      # things, so an instantaneous "nothing running" is normal mid-run. The
      # exit code and summary come from the tallies scripts reported, not from
      # walking the tree.
      if TEST_MODE in state.local_flags:
        let now = get_mono_time()
        if test_started_at == MonoTime.high:
          test_started_at = now
          worker.test_last_activity = now
          notice "test mode started"

        var any_running = false
        var running_scripts: seq[string]
        state.things.value.walk_tree proc(thing: Thing) =
          if ?thing.script_ctx and thing.script_ctx.running:
            any_running = true
            running_scripts.add thing.id

        if any_running or worker.failed.len > 0:
          worker.test_last_activity = now

        let elapsed = now - test_started_at
        # Log progress every 30 seconds
        if elapsed.in_seconds.int mod 30 == 0 and elapsed.in_seconds.int > 0 and
            elapsed.in_milliseconds.int mod 1000 < 100:
          notice "test mode running",
            elapsed = elapsed, scripts = running_scripts

        if QUITTING in state.local_flags:
          discard # already finishing; wait for it to propagate
        elif elapsed > test_timeout:
          notice "test mode timeout",
            elapsed = elapsed, scripts = running_scripts
          inc worker.test_error_count
          worker.finish_test_run(timed_out = true)
        elif now - worker.test_last_activity > test_quiesce_grace:
          worker.finish_test_run(timed_out = false)

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
        # Agent queries hold in PENDING until a top-level file scan has run
        # (their handler only schedules one — see bots.nim): any reload the
        # scan triggers ran to completion above, so answers can't observe a
        # half-reloaded unit. Promote them now; the READY write re-fires
        # their watch, which answers the query.
        for unit in state.things.value:
          if unit of Bot and EPHEMERAL in unit.global_flags:
            let bot = Bot(unit)
            if bot.query.state == PENDING:
              var q = bot.query
              q.state = READY
              bot.query = q

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

    # Crash on purpose (a wedged worker must not zombie on), but exit directly
    # rather than re-raising: the unwind crosses godot-nim's C++ frames and
    # dies in libc++ ("recursive_mutex lock failed" + SIGABRT) with a
    # misleading traceback from whatever the main thread happened to be doing.
    # The error log above carries the real story; exit with it intact.
    stderr.write_line "worker thread died: " & e.msg
    stderr.write_line e.get_stack_trace
    quit(1)

  try:
    if NEEDS_RESTART in state.local_flags:
      if ?listen_address:
        private_access Reactor
        Ed.thread_ctx.reactor.socket.close
      state.pop_flag NEEDS_RESTART

    Ed.thread_ctx.tick

    # The worker thread is exiting (quit or NEEDS_RESTART → relaunch). Release
    # the context's bodies + buffers; without this every restart leaks the whole
    # worker context and its voxel bodies (the body closures pin it — ORC can't
    # collect the cycle, so it needs the explicit ed EdContext.destroy).
    worker_ctx.destroy()
  except Exception:
    discard

proc launch_worker*(
    ctx: EdContext, state: GameState
): system.Thread[tuple[ctx: EdContext, state: GameState]] =
  worker_lock.acquire
  result.create_thread(worker_thread, (ctx, state))
  work_done.wait(worker_lock)
  worker_lock.release
