import std/[monotimes, os, json, math, random, net, strformat]
import pkg/[godot, metrics]
when defined(metrics):
  import metrics_server
from dotenv import nil
import
  godotapi/[
    input, input_event, gd_os, node, scene_tree, packed_scene, sprite, control,
    viewport, viewport_texture, texture, image, performance, label, theme,
    dynamic_font, resource_loader, main_loop, project_settings, input_map,
    input_event_action, input_event_key, input_event, global_constants,
    scroll_container, voxel_server, world_environment, camera, world,
    physics_direct_space_state,
  ]

import ui/virtual_joystick
import
  core, types, gdutils, controllers, models/[serializers, things, colors, builds]
import libs/fd_tracking

var next_perf_log {.threadvar.}: MonoTime
var next_voxmem_log {.threadvar.}: MonoTime
var next_stats_update {.threadvar.}: MonoTime
var last_frame_at {.threadvar.}: MonoTime
var slow_frame_log {.threadvar.}: int ## 0 unread, 1 on, -1 off
var slow_frame_ms {.threadvar.}: float ## threshold; ENU_SLOW_FRAME_MS

# Immediate process exit that runs no atexit handlers, C++ destructors, or Nim
# GC teardown. Used to end test-mode runs without triggering Godot's headless
# teardown (which segfaults) or Nim's `quit` (which re-enters ed's locks while
# we're inside a flag-change callback, aborting on a recursive mutex).
proc c_exit(code: cint) {.importc: "_Exit", header: "<stdlib.h>".}

if file_exists(".env"):
  dotenv.overload()

when defined(metrics):
  set_system_metrics_automatic_update(false)

EdContext.init_metrics "main", "worker"

proc format_bytes(bytes: SomeNumber): string =
  let b = bytes.float
  if b < 1024:
    fmt"{b.int} B"
  elif b < 1024 * 1024:
    fmt"{(b / 1024):.1f} KB"
  else:
    fmt"{(b / 1024 / 1024):.2f} MB"

proc get_network_stats(): string =
  ## Get network bytes sent/received stats from worker thread via GameState
  let conn_count = state.net_connections
  let bytes_sent = state.net_bytes_sent
  let bytes_recv = state.net_bytes_received

  if conn_count == 0:
    result =
      \"net: no conn (sent: {format_bytes(bytes_sent)}, recv: {format_bytes(bytes_recv)})"
  else:
    result =
      \"net: {conn_count} conn, sent: {format_bytes(bytes_sent)}, recv: {format_bytes(bytes_recv)}"

# saved state when restarting worker thread
const savable_flags =
  {CONSOLE_VISIBLE, MOUSE_CAPTURED, FLYING, GOD, ALT_WALK_SPEED, ALT_FLY_SPEED}

const SPAWN_GATE_TIMEOUT = 30.seconds
  ## Cap on how long the reveal waits for the pre-PLAYERS builds to settle
  ## after LOAD_SCREEN clears — an animated build never settles, and a slow
  ## mesh must not hold the load hostage.


var environment_cache {.threadvar.}: Table[string, Environment]

gdobj Game of Node:
  var
    reticle: Control
    load_screen: Control
    scaled_viewport: Viewport
    triggered = false
    saved_mouse_captured_state = false
    stats: Label
    last_tool = BLUE_BLOCK
    saved_mouse_position: Vector2
    rescale_at = get_mono_time()
    update_metrics_at = get_mono_time()
    force_quit_at = MonoTime.high
    node_controller: NodeController
    script_controller: ScriptController
    left_stick: VirtualJoystick
    booted: bool
      ## The LoadScreen covers the viewport from the first frame; once a load
      ## actually starts (or a boot timeout fires) we hand control of the splash
      ## to the spawn gate (SPAWN_HELD). See process().
    boot_deadline: MonoTime
    gate_ids: seq[string]
      ## Build ids snapshotted the moment the server cleared LOAD_SCREEN — by
      ## ed ordering, exactly this machine's copy of the pre-PLAYERS units.
      ## SPAWN_HELD stays on until every one has rendered here.
    gate_waiting: bool
    gate_deadline: MonoTime
    gate_started: MonoTime
    screenshot_camera_node: Camera
    screenshot_viewport_node: Viewport

  method process*(delta: float) =
    if state.is_nil or state.nodes.game != self:
      # A scene reload (the NEEDS_RESTART worker-restart path) instantiates a
      # fresh Game whose init replaces the global `state`; this superseded
      # node can still get a frame or two before teardown. It must not touch
      # the shared state — its node_controller's pending things would
      # add_to_scene against the new instance's half-initialized nodes
      # (state.nodes.data is nil until the new ready() runs): a nil-parent
      # SIGSEGV observed when a client self-restarted mid-join.
      return
    Ed.thread_ctx.tick
    inc state.frame_count
    self.node_controller.drain_pending()

    let time = get_mono_time()
    when defined(metrics):
      if self.update_metrics_at < time:
        update_thread_metrics()
        self.update_metrics_at = time + 10.seconds

    # Opt-in hitch log (same env as PERF): every frame gap over 100 ms is a
    # stutter the player felt — log each one with its true length, since the
    # 2s PERF sampling undercounts short hitches. One clock compare per frame.
    if slow_frame_log == 0:
      slow_frame_log = if get_env("ENU_PERF_LOG") != "": 1 else: -1
      slow_frame_ms = 100.0
      try:
        let t = get_env("ENU_SLOW_FRAME_MS")
        if t != "":
          slow_frame_ms = t.parse_float
      except ValueError:
        discard
    if slow_frame_log == 1:
      if last_frame_at != MonoTime():
        let gap = (time - last_frame_at).in_milliseconds.float
        if gap > slow_frame_ms:
          info "SLOW_FRAME", ms = gap
      last_frame_at = time

    # Opt-in perf sampling (ENU_PERF_LOG=1): one "PERF" line every ~2s with
    # render-side metrics for before/after comparisons (e.g. greedy meshing).
    # vertex_mem / draw_calls / objects are the geometry cost; fps / frame_ms
    # the resulting cost. Off by default — the env check only runs on the 2s
    # tick, never per frame.
    if time > next_perf_log and get_env("ENU_PERF_LOG") != "":
      next_perf_log = time + 2.seconds
      let vtasks = get_stats()["tasks"].as_dictionary
      info "PERF",
        fps = get_monitor(TIME_FPS),
        frame_ms = get_monitor(TIME_PROCESS) * 1000.0,
        vertex_mem_kb = (get_monitor(RENDER_VERTEX_MEM_USED) / 1024.0).int,
        objects = get_monitor(RENDER_OBJECTS_IN_FRAME).int,
        draw_calls = get_monitor(RENDER_DRAW_CALLS_IN_FRAME).int,
        video_mem_mb = (get_monitor(RENDER_VIDEO_MEM_USED) / 1048576.0).int,
        # VoxelServer in-flight task gauges (live counts, not cumulative —
        # for totals, sum the per-terrain TERRAIN `meshed` counter instead).
        mesh_queue = parse_int($vtasks["meshing"]),
        gen_queue = parse_int($vtasks["generation"])

    # Opt-in resident voxel memory sampling (ENU_VOXEL_MEM_LOG=1): thread-heap
    # occupancy + per-store counters, for before/after comparisons of the
    # resident voxel representation. Same pattern as ENU_PERF_LOG above.
    if time > next_voxmem_log and get_env("ENU_VOXEL_MEM_LOG") != "":
      next_voxmem_log = time + 5.seconds
      let s = voxel_mem_stats(state.things)
      info "VOXMEM main",
        occupied_kb = get_occupied_mem() div 1024,
        builds = s.builds,
        lv_chunks = s.lv_chunks,
        lv_voxels = s.lv_voxels,
        packed = s.packed,
        edit_chunks = s.edit_chunks,
        edit_voxels = s.edit_voxels

    # Wait for the level's config (level_dir/data_dir set by load_level) before
    # syncing window state: this is a whole-Config read-modify-write, and doing
    # it from a pre-load copy would clobber the worker's paths (lost update).
    if state.config.data_dir != "" and
        state.config.full_screen != is_window_fullscreen():
      state.config_value.value:
        full_screen = not state.config.full_Screen

    if state.config.show_stats:
      # Refresh the overlay at ~10 Hz, not every frame: the tree walk and full
      # string interpolation below are a per-frame main-thread cost, and the
      # label re-emitting its whole text every frame is a canvas upload the
      # render thread doesn't need — a stats readout reads identically to the
      # eye at 10 Hz. The 300-frame leak log keeps its own cadence, so only
      # walk the tree when at least one consumer is due.
      let stats_due = time > next_stats_update
      let log_due = state.frame_count mod 300 == 0
      if stats_due or log_due:
        var thing_count = 0
        # Loaded chunk entries across all builds — the number voxel paging
        # actually moves (chunk values live inside their tables, so the object
        # count doesn't reflect page-in/out).
        var chunk_count = 0
        state.things.value.walk_tree proc(thing: Thing) =
          inc thing_count
          if thing of Build and ?Build(thing).voxels:
            chunk_count += Build(thing).voxels.packed_chunks.len
            chunk_count += Build(thing).voxels.chunk_deltas.len

        if stats_due:
          next_stats_update = time + 100.milliseconds
          let fps = get_monitor(TIME_FPS)
          let vram = get_monitor(RENDER_VIDEO_MEM_USED)
          self.stats.text =
            \"""
            FPS: {fps}
            scale_factor: {state.scale_factor}
            vram: {vram}
            things: {thing_count}
            ed objects: {Ed.thread_ctx.len}
            chunks: {chunk_count}
            ed mem: {state.ed_mem div 1024} KiB
            level: {state.level_name}
            {get_network_stats()}
            {get_stats()}
            """

        # Periodic main-thread counterpart of "worker stats": ed object growth
        # here is how reload/sync leaks surface (see docs/notes on the reload
        # leaks) — keep it greppable.
        if log_due:
          info "main stats", ed_objects = Ed.thread_ctx.len, things = thing_count,
            chunks = chunk_count
    state.voxel_tasks =
      parse_int($get_stats()["tasks"].as_dictionary["main_thread"])

    if time > self.rescale_at:
      self.rescale_at = MonoTime.high
      self.rescale()

    if time > self.force_quit_at:
      state.pop_flag QUITTING

    if SCENE_READY notin state.local_flags:
      state.push_flag SCENE_READY

    # Loading splash. The LoadScreen node ships visible, so the boot goes
    # straight from Godot's own splash into ours — no flash of empty scene +
    # UI. It stays up unconditionally until a load actually starts (or an 8s
    # safety timeout), then follows this machine's spawn gate: up and 3D
    # render off while the player is held at the spawn, revealed the frame
    # the gate releases.
    if not self.load_screen.is_nil:
      if not self.booted and (
        LOADING_LEVEL in state.global_flags or
        LOAD_SCREEN in state.global_flags or time > self.boot_deadline
      ):
        self.booted = true
      let show =
        if self.booted: SPAWN_HELD in state.local_flags else: true
      if self.load_screen.visible != show:
        self.load_screen.visible = show
      # The splash is opaque, so don't spend the GPU drawing the 3D viewport
      # behind it while it's up.
      if not self.scaled_viewport.is_nil:
        let mode = if show: UPDATE_DISABLED else: UPDATE_ALWAYS
        if self.scaled_viewport.render_target_update_mode != mode:
          self.scaled_viewport.render_target_update_mode = mode

  method physics_process*(delta: float) =
    if state.is_nil or state.nodes.game != self:
      return

    # Spawn gate, second half: LOAD_SCREEN has cleared (the ready() watch
    # snapshotted the pre-PLAYERS builds into gate_ids), so release this
    # machine's player once every snapshot build's DATA has rendered locally:
    #
    # - pending_block_updates == 0 for every gate build. This is exact, not
    #   a settle heuristic: the engine counts required-but-unloaded blocks,
    #   queued mesh updates, and in-flight meshes, and build_node publishes
    #   a floor of 1 until the terrain's streaming has actually started
    #   (has_stream_started) — so 0 can only mean "everything the viewer
    #   needs is loaded and meshed", never "nothing requested yet".
    # - collision under the player. Collision meshes trail the voxel data,
    #   and a player released early sinks into the still-forming spawn hill
    #   and wedges there. Runs here rather than in process() because space
    #   queries are only valid in the physics step.
    #
    # Deliberately NOT gated on scripts (ASAP_MODE): a persisted gate unit's
    # voxels render in the data phase via prefill, while its script — usually
    # decoration or animation (the island's water is `play(8.0)`, the gull an
    # endless flap loop) — doesn't run until every unit's data has loaded,
    # and an animated one never finishes at all. Frame meshes are likewise
    # held (FramePlayer defers renders under SPAWN_HELD) so playback can't
    # churn the counters mid-gate; they bake right after the reveal.
    #
    # The deadline backstop covers a build that never settles and a spawn
    # with genuinely nothing below it.
    if self.gate_waiting:
      let time = get_mono_time()
      var rendered = true
      state.things.value.walk_tree proc(thing: Thing) =
        if thing of Build and thing.id in self.gate_ids:
          if thing.pending_block_updates != 0:
            rendered = false
      if rendered and ?state.player and not state.nodes.player.is_nil:
        # Short ray: the spawn pose stands the player ~1.5m above the ground,
        # so support must be close below. A long ray can hit the sea-level
        # ground under a still-unformed spawn hill and release into a sink.
        let origin = state.player.transform.origin
        let space = self.get_viewport().find_world().direct_space_state
        let hit = space.intersect_ray(
          origin,
          origin - vec3(0, 3, 0),
          exclude = new_array(state.nodes.player.to_variant),
        )
        if hit.len == 0:
          rendered = false
        else:
          # De-embed before unfreezing: a start_transform that sits the
          # capsule inside the surface leaves move_and_slide unable to
          # depenetrate — the player is wedged until they fly out. The
          # capsule rests with its origin ~0.9 above the surface, so lift
          # anything closer than that to a safe height and let gravity
          # settle the last few centimetres.
          let surface_y = hit["position"].as_vector3.y
          if origin.y < surface_y + 0.9:
            var t = state.player.transform
            t.origin.y = surface_y + 1.2
            state.player.transform = t
            info "spawn gate: lifted player clear of the surface",
              from_y = origin.y, to_y = t.origin.y
      if rendered or time > self.gate_deadline:
        if not rendered:
          error "spawn gate timed out; revealing anyway",
            gate_ids = self.gate_ids
        else:
          info "spawn gate: released",
            waited_ms = (time - self.gate_started).in_milliseconds
        self.gate_waiting = false
        self.gate_ids = @[]
        state.pop_flag SPAWN_HELD

  proc rescale*() =
    let vp = self.get_viewport().size
    let megapixels =
      if ?state.config.megapixels_override:
        state.config.megapixels_override
      else:
        state.config.megapixels
    state.scale_factor = sqrt(megapixels * 1_000_000.0 / (vp.x * vp.y))

    self.scaled_viewport.size = vp * state.scale_factor
    self.scaled_viewport.get_texture.flags =
      if megapixels >= 1.0: FLAG_FILTER else: 0

    info "Rescaled viewport", size = self.scaled_viewport.size

  method notification*(what: int) =
    if what == main_loop.NOTIFICATION_WM_QUIT_REQUEST:
      state.push_flag QUITTING

    if what == main_loop.NOTIFICATION_WM_ABOUT:
      alert \"Enu {enu_version}\n\n© 2025 Scott Wadden", "Enu"

  proc add_platform_input_actions() =
    let suffix = "." & host_os
    for action in get_actions():
      let action = action.as_string()
      if suffix in action:
        let name = action.replace(suffix, "")
        if has_action(name):
          erase_action(name)
        add_action(name)
        for event in get_action_list(action):
          let event = event.as_object(InputEvent)
          action_add_event(name, event)
        erase_action(action)

  proc init*() =
    info "game.init() starting"
    self.process_priority = -100

    let screen_scale =
      if host_os == "macos":
        get_screen_scale(-1)
      else:
        get_screen_dpi(-1).float / 96.0

    var args = get_cmdline_args().to_seq
    var temp_workdir = false
    let work_dir = block:
      let i = args.find("--temp-workdir")
      if i > -1:
        temp_workdir = true
        args.delete(i)
        let temp = get_temp_dir() / ("enu-test-" & $get_current_process_id())
        create_dir temp
        temp
      else:
        get_user_data_dir()

    var initial_user_config = load_user_config(work_dir)

    echo "== WORKDIR " & work_dir

    Ed.thread_ctx = EdContext.init(
      id = \"main-{generate_id()}",
      chan_size = 2000,
      buffer = true,
      label = "main",
      max_recv_duration = (1.0 / 30.0).seconds,
      # No mem_limit: the node ctx is a full clone (subscribes partial = false),
      # and full clones never evict — everything they hold is synced state
      # something may read back, so there's no safe residue to drop. Voxel
      # memory is managed at the worker (the partial replica), which caches
      # chunks per-key and sheds under its own budget. (ed enforces this: a
      # full clone ignores mem_limit. See interest-tiers-design.md.)
    )

    state = GameState.init
    state.nodes.game = self

    var uc = initial_user_config
    assert not state.is_nil

    randomize()

    var connect_address_override = ""
    var listen_address_override = ""
    var level_dir_override = ""
    var test_mode = false
    var minimized = false

    block:
      let i = args.find("--connect")
      if i > -1 and args.len > i + 1:
        connect_address_override = args[i + 1]
        args.delete(i .. i + 1)
    block:
      let i = args.find("--listen")
      if i > -1:
        if args.len > i + 1:
          listen_address_override = args[i + 1]
          args.delete(i .. i + 1)
        else:
          listen_address_override = "0.0.0.0"
          args.delete(i)
    block:
      let i = args.find("--level-dir")
      if i > -1 and args.len > i + 1:
        level_dir_override = args[i + 1]
        args.delete(i .. i + 1)
    block:
      let i = args.find("--enu-test")
      if i > -1:
        test_mode = true
        args.delete(i)
    block:
      let i = args.find("--minimized")
      if i > -1:
        minimized = true
        args.delete(i)
    block:
      let i = args.find("--level")
      if i > -1:
        let parts = args[i + 1].split("/")
        uc.world = some(parts[0])
        uc.level = some(parts[1])
        args.delete(i .. i + 1)

    raise_fd_limit()

    if ?get_env("ENU_LISTEN_ADDRESS") and not ?listen_address_override:
      listen_address_override = get_env("ENU_LISTEN_ADDRESS")
    if ?get_env("ENU_CONNECT_ADDRESS") and not ?connect_address_override:
      connect_address_override = get_env("ENU_CONNECT_ADDRESS")
    if ?listen_address_override and ?connect_address_override:
      fail "Cannot set both ENU_LISTEN_ADDRESS and ENU_CONNECT_ADDRESS"

    if ?saved_state.connect_address:
      connect_address_override = saved_state.connect_address

    if host_os == "macosx" and not saved_state.restarting:
      global_menu_add_item(
        "Help", "Documentation", "help".to_variant, "".to_variant
      )
      global_menu_add_item("Help", "Web Site", "site".to_variant, "".to_variant)
      if connect_address_override == "":
        global_menu_add_separator("Help")
        global_menu_add_item(
          "Help", "Launch Tutorial", "tutorial".to_variant, "".to_variant
        )

    when host_os == "ios":
      state.push_flag TOUCH_CONTROLS
      let share = join_path(get_executable_path().parent_dir(), "share")
    else:
      # state.push_flag TOUCH_CONTROLS
      let share =
        join_path(get_executable_path().parent_dir(), "..", "..", "..", "share")

    state.config_value.value:
      screen_scale = screen_scale
      work_dir = work_dir
      font_size = uc.font_size ||= 20
      toolbar_size = uc.toolbar_size ||= 100
      world = uc.world ||= "tutorial"
      level = uc.level ||= value.world & "-1"
      run_server = uc.run_server ||= false
      show_stats = uc.show_stats ||= false
      megapixels = uc.megapixels ||= 2.0
      full_screen = uc.full_screen ||= true
      semicolon_as_colon = uc.semicolon_as_colon ||= false
      lib_dir = share
      connect_address = uc.connect_address ||= ""
      listen_address = uc.listen_address ||= ""
      player_color = uc.player_color ||= color(rand(1.0), rand(1.0), rand(1.0))
      world_dir = join_path(value.work_dir, value.world)
      level_dir = join_path(value.world_dir, value.level)
      walk_speed = uc.walk_speed ||= 500
      fly_speed = uc.fly_speed ||= 1500
      alt_walk_speed = uc.alt_walk_speed ||= 1000
      alt_fly_speed = uc.alt_fly_speed ||= 250
      mouse_sensitivity = uc.mouse_sensitivity ||= 5.0
      gamepad_sensitivity = uc.gamepad_sensitivity ||= 2.5
      invert_gamepad_y_axis = uc.invert_gamepad_y_axis ||= false
      environment = uc.environment ||= "default"
      auto_show_console = uc.auto_show_console ||= true
      megapixels_override = environments[value.environment]

    if ?listen_address_override:
      state.config_value.value:
        listen_address_override = listen_address_override

    if ?connect_address_override:
      state.config_value.value:
        connect_address_override = connect_address_override

    if ?level_dir_override:
      let level_file = level_dir_override / "level.json"
      if not file_exists(level_file):
        fail "Level not found: " & level_dir_override & " (no level.json)"
      let parts = level_dir_override.split_path
      let world_dir_path = parts.head

      let new_level = parts.tail
      let new_world = world_dir_path.split_path.tail
      var final_world_dir = world_dir_path
      var final_level_dir = level_dir_override

      if temp_workdir:
        # Isolate from the source: copy the level into the temp work dir and run
        # against the copy, so a test run never modifies — or deletes scripts
        # from — the real level.
        final_world_dir = join_path(work_dir, new_world)
        final_level_dir = join_path(final_world_dir, new_level)
        copy_dir(level_dir_override, final_level_dir)

      state.config_value.value:
        level = new_level
        world = new_world
        world_dir = final_world_dir
        level_dir = final_level_dir

    if test_mode:
      notice "test mode enabled"
      state.push_flag TEST_MODE

    state.set_flag(GOD, uc.god_mode ||= false)

    if minimized:
      # Launch out of the way (test runs, MCP-managed instances): minimize and
      # skip fullscreen. The screenshot path force-draws a minimized window, so
      # captures still work.
      set_window_minimized true
    else:
      set_window_fullscreen state.config.full_screen
    when defined(metrics):
      let metrics_port =
        if ?get_env("ENU_METRICS_PORT"):
          get_env("ENU_METRICS_PORT").parse_int
        else:
          8000
      start_metrics_server("0.0.0.0", metrics_port)

    self.add_platform_input_actions()

    when defined(dist):
      let exe_dir = parent_dir get_executable_path()
      if host_os == "macosx":
        state.config_value.value:
          lib_dir = join_path(exe_dir.parent_dir, "Resources", "share")
      elif host_os == "windows":
        state.config_value.value:
          lib_dir = join_path(exe_dir, "share")
      elif host_os == "linux":
        state.config_value.value:
          lib_dir = join_path(exe_dir.parent_dir, "lib", "share")

    self.node_controller = NodeController.init
    self.script_controller = ScriptController.init

    save_user_config(uc)
    info "game.init() complete"

  proc set_panel_width() =
    let
      theme = self.find_node("LeftPanel").as(Container).theme
      mono_font = theme.get_font("font", "MonoButton").as(DynamicFont)
      font_width = mono_font.get_string_size(" ".repeat(34)).x
      viewport_width = self.get_viewport().size.x

    if font_width > viewport_width / 2.0:
      state.push_flag FULL_WIDTH_PANELS
    else:
      state.pop_flag FULL_WIDTH_PANELS

  proc set_font_size(size: int) =
    if state.config.font_size != size:
      var user_config = load_user_config()
      state.config_value.value:
        font_size = size

    let
      theme = find("LeftPanel", Container).theme
      font = theme.default_font.as(DynamicFont)
      bold_font = theme.get_font("bold_font", "RichTextLabel").as(DynamicFont)
      icon_font = theme.get_font("font", "IconButton").as(DynamicFont)
      mono_font = theme.get_font("font", "MonoButton").as(DynamicFont)
      label_font = theme.get_font("font", "Label").as(DynamicFont)
      normal_font = theme.get_font("font", "LineEdit").as(DynamicFont)

    font.size = (size.float * state.config.screen_scale).int
    bold_font.size = font.size
    icon_font.size = font.size
    mono_font.size = font.size
    label_font.size = font.size
    normal_font.size = font.size

    self.set_panel_width()

  method on_gui_input*(event: InputEvent, name: string) =
    if event of InputEventMouseButton:
      case name
      of "Editor":
        debug "pushing EDITOR_FOCUSED", topics = "state"
        state.push_flag EDITOR_FOCUSED
      of "Console":
        debug "pushing CONSOLE_FOCUSED", topics = "state"
        state.push_flag CONSOLE_FOCUSED
      of "Settings":
        debug "pushing SETTINGS_FOCUSED", topics = "state"
        state.push_flag SETTINGS_FOCUSED
      of "RightPanel":
        debug "pushing DOCS_FOCUSED", topics = "state"
        state.push_flag DOCS_FOCUSED
      else:
        warn "Couldn't focus control", name

  method load_environment(environment: string) =
    let env =
      state.nodes.game.find_node("Level").get_node("WorldEnvironment") as
      WorldEnvironment
    if environment notin environment_cache:
      let res = \"res://environments/{environment}.tres"

      var environment_res: Environment = nil
      if environment != "none":
        environment_res = load(res) as Environment
        if not ?environment_res:
          logger("err", \"Environment {environment} not found")
          return
      environment_cache[environment] = environment_res
    env.environment = environment_cache[environment]
    state.config_value.value:
      megapixels_override = environments[environment]
    info "Changed game mode", environment

  method ready*() =
    try:
      info "game.ready() starting"
      state.nodes.data = state.nodes.game.find_node("Level").get_node("data")
      assert not state.nodes.data.is_nil
      self.scaled_viewport =
        self.get_node("ViewportContainer/Viewport") as Viewport
      self.screenshot_viewport_node = gdnew[Viewport]()
      self.screenshot_viewport_node.name = "ScreenshotViewport"
      self.screenshot_viewport_node.size = vec2(640, 360)
      self.screenshot_viewport_node.render_target_update_mode = UPDATE_ALWAYS
      self.add_child(self.screenshot_viewport_node)
      self.screenshot_viewport_node.world = self.scaled_viewport.find_world()
      self.screenshot_camera_node = gdnew[Camera]()
      self.screenshot_camera_node.name = "ScreenshotCamera"
      self.screenshot_viewport_node.add_child(self.screenshot_camera_node)
      self.screenshot_camera_node.make_current()
      state.screenshot_camera = self.screenshot_camera_node
      state.screenshot_viewport = self.screenshot_viewport_node

      self.bind_signals(self.get_viewport(), "size_changed")
      self.bind_signals(self.get_tree(), "global_menu_action")
      assert not self.scaled_viewport.is_nil
      self.get_tree().auto_accept_quit = false
      self.set_font_size(state.config.font_size)
      info "loading environment", env = state.config.environment
      self.load_environment(state.config.environment)
      info "config", config = state.config
      self.reticle = self.find_node("Reticle").as(Control)
      self.load_screen = self.find_node("LoadScreen").as(Control)
      # Hand the splash over to the LOAD_SCREEN flag once a load starts, or
      # after this timeout so it can never stick (e.g. a client that never runs
      # a local load).
      self.boot_deadline = get_mono_time() + 8.seconds
      self.stats = self.find_node("stats").as(Label)
      self.left_stick = find("LeftStick", VirtualJoystick)
      self.stats.visible = state.config.show_stats
    except Exception as e:
      error "game.ready() failed", msg = e.msg, stacktrace = e.get_stack_trace()
      raise e

    state.config_value.changes:
      if change.item.full_screen != state.config.full_screen:
        set_window_fullscreen state.config.full_screen
      if change.item.environment != state.config.environment or
          change.item.environment_override != state.config.environment_override:
        let env =
          if ?state.config.environment_override:
            state.config.environment_override
          else:
            state.config.environment
        self.load_environment(env)

      if change.item.megapixels != state.config.megapixels:
        state.config_value.value:
          megapixels_override = 0.0
        self.rescale_at = get_mono_time()

      if change.item.megapixels_override != state.config.megapixels_override:
        self.rescale_at = get_mono_time()

      if change.item.font_size != state.config.font_size:
        self.set_font_size(state.config.font_size)

    state.global_flags.changes:
      if LOAD_SCREEN.added:
        # Splash phase: hold this machine's player frozen at the spawn while
        # the units ahead of the PLAYERS load_order step stream in.
        self.gate_waiting = false
        self.gate_ids = @[]
        state.push_flag SPAWN_HELD
      elif LOAD_SCREEN.removed:
        # Snapshot the gate set here, in the watch, not from process() a tick
        # later: ed applied the pre-PLAYERS units ahead of this flag removal
        # and nothing after it has landed yet, so the builds present right now
        # are exactly the units the reveal must wait on.
        var ids: seq[string]
        state.things.value.walk_tree proc(thing: Thing) =
          if thing of Build:
            ids.add thing.id
        self.gate_ids = ids
        self.gate_waiting = true
        self.gate_started = get_mono_time()
        self.gate_deadline = self.gate_started + SPAWN_GATE_TIMEOUT
        info "spawn gate: waiting for local render", gate_ids = ids

    state.player_value.changes:
      if added and ?change.item and saved_state.restarting:
        change.item.transform = saved_state.transform
        change.item.rotation = saved_state.rotation

        for flag in saved_state.flags:
          state.push_flag(flag)

        saved_state.restarting = false

    state.local_flags.changes(false):
      if QUITTING.added:
        # We don't quit until the worker thread acks by popping the `Quitting`
        # flag, giving it a chance to save and cleanup. If the worker thread is
        # stuck, killed, or hasn't fully started because it's trying to connect
        # to a server, it won't pop the flag, so we force it after a timeout.
        if TEST_MODE in state.local_flags:
          # In test mode, pop immediately - test_exit_code is a EdValue so it syncs with the flag
          state.pop_flag QUITTING
        else:
          self.force_quit_at = get_mono_time() + 2.seconds
      elif QUITTING.removed:
        let exit_code =
          if TEST_MODE in state.local_flags and state.test_exit_code >= 0:
            state.test_exit_code
          else:
            0
        if TEST_MODE in state.local_flags:
          # Headless Godot's dummy rasterizer segfaults during teardown,
          # freeing render resources it never allocated (NULL RID frees in
          # visual_server_raster). The tests have already finished and their
          # exit code is known, so exit the process directly rather than
          # letting Godot's shutdown crash and mask the result. --temp-workdir
          # means there's nothing to persist. We're inside a flag-change
          # callback holding ed's lock, so we can't use Nim's `quit` (its
          # teardown re-enters the lock); c_exit terminates with no cleanup.
          flush_file stdout
          flush_file stderr
          c_exit(exit_code.cint)
        self.get_tree().quit(exit_code)

      if NEEDS_RESTART.removed:
        saved_state.transform = state.player.transform
        saved_state.rotation = state.player.rotation
        saved_state.flags = {}
        saved_state.connect_address = state.config.connect_address

        for flag in state.local_flags:
          if flag in savable_flags:
            saved_state.flags.incl(flag)

        saved_state.restarting = true
        discard self.get_tree.reload_current_scene()

      if CONNECTING.added:
        state.status_message =
          \"""
          # Connecting...

          Trying to connect to {state.config.connect_address}.
          """
      elif CONNECTING.removed:
        state.status_message = ""

      if MOUSE_CAPTURED.added:
        let center = self.get_viewport().get_visible_rect().size * 0.5
        self.saved_mouse_position = self.get_viewport().get_mouse_position()
        warp_mouse_position(center)
        set_mouse_mode MOUSE_MODE_CAPTURED
      elif MOUSE_CAPTURED.removed:
        set_mouse_mode MOUSE_MODE_VISIBLE
        warp_mouse_position(self.saved_mouse_position)

      if RETICLE_VISIBLE.added:
        self.reticle.visible = true
      elif RETICLE_VISIBLE.removed:
        self.reticle.visible = false

    if TOUCH_CONTROLS notin state.local_flags:
      state.push_flag MOUSE_CAPTURED
    state.push_flag VIEWPORT_FOCUSED

    state.queued_action_value.changes:
      if added and change.item != "":
        # First byte is the edge: '+' press, '-' release (see
        # press_action/release_action in host_bridge).
        let queued = state.queued_action
        state.queued_action = ""
        var ev = gdnew[InputEventAction]()
        ev.action = queued[1 .. ^1]
        ev.pressed = queued[0] == '+'
        parse_input_event(ev)

  method on_size_changed() =
    self.rescale_at = get_mono_time()
    self.set_panel_width()

  method on_global_menu_action(action: string, id: string) =
    if action == "help":
      discard shell_open("http://getenu.com/docs/intro.html")
    elif action == "site":
      discard shell_open("http://getenu.com")
    elif action == "settings":
      state.push_flag SETTINGS_VISIBLE
    elif action == "openurl":
      logger("info", \"Open URL: {id}")
    elif action == "tutorial":
      state.config_value.value:
        level_dir = ""
      state.player.transform = Transform.init(origin = vec3(0, 2, 0))
      state.player.rotation = 0
      change_loaded_level("tutorial-1", "tutorial")
    else:
      warn "Unknown action", action, id

  proc switch_world(diff: int) =
    var config = state.config
    if diff != 0:
      change_loaded_level(
        resolve_level_name(state.config.world, state.config.level, diff),
        state.config.world,
      )
    else:
      # force a reload of the current world
      let current_level = state.config.level_dir
      state.config_value.value:
        level_dir = ""
      state.config_value.value:
        level_dir = current_level

  method unhandled_input*(event: InputEvent) =
    if event of InputEventKey:
      let event = InputEventKey(event)
      # Left alt support. raw_code is an enu specific addition
      if (host_os == "macosx" and event.raw_code == 58) or
          (host_os == "windows" and event.raw_code == 56) or
          (host_os == "linux" and event.raw_code == 65513):
        if event.pressed:
          state.push_flag COMMAND_MODE
        else:
          state.pop_flag COMMAND_MODE

    if EDITOR_VISIBLE in state.local_flags or DOCS_VISIBLE in state.local_flags or
        CONSOLE_VISIBLE in state.local_flags:
      if event.is_action_pressed("zoom_in"):
        state.config_value.value:
          font_size = state.config.font_size + 1
      elif event.is_action_pressed("zoom_out"):
        state.config_value.value:
          font_size = state.config.font_size - 1
    else:
      if event.is_action_pressed("next"):
        state.update_action_index(1)

      if event.is_action_pressed("previous"):
        state.update_action_index(-1)

    # NOTE: alt+enter isn't being picked up on windows if the editor is
    # open. Needs investigation.
    if event.is_action_pressed("toggle_fullscreen") or (
      host_os == "windows" and COMMAND_MODE in state.local_flags and
      EDITOR_VISIBLE in state.local_flags and event of InputEventKey and
      event.as(InputEventKey).scancode == KEY_ENTER
    ):
      state.config_value.value:
        full_screen = not state.config.full_screen
    elif event.is_action_pressed("settings"):
      state.set_flag SETTINGS_VISIBLE, SETTINGS_VISIBLE notin state.local_flags
    elif event.is_action_pressed("next_level"):
      self.switch_world(+1)
    elif event.is_action_pressed("prev_level"):
      self.switch_world(-1)
    elif event.is_action_pressed("save_and_reload"):
      state.pop_flag PLAYING
      state.push_flag RESETTING_VM
      self.switch_world(0)
      state.pop_flag RESETTING_VM
      self.get_tree().set_input_as_handled()
    elif event.is_action_pressed("pause"):
      state.paused = not state.paused
    elif event.is_action_pressed("clear_console"):
      state.console.log.clear()
    elif event.is_action_pressed("toggle_console"):
      if CONSOLE_VISIBLE in state.local_flags:
        state.pop_flags CONSOLE_VISIBLE, CONSOLE_FOCUSED
      else:
        state.push_flags CONSOLE_VISIBLE, CONSOLE_FOCUSED
    elif event.is_action_pressed("quit"):
      if host_os != "macosx":
        state.push_flag QUITTING
    elif event.is_action_pressed("change_mode"):
      var mode = state.config.environment
      let keys = environments.keys.to_seq
      while (mode = keys.sample; mode == state.config.environment):
        discard
      state.config_value.value:
        environment = mode
    elif EDITOR_VISIBLE notin state.local_flags:
      if event.is_action_pressed("toggle_mouse_captured"):
        state.set_flag MOUSE_CAPTURED, MOUSE_CAPTURED notin state.local_flags
        self.get_tree().set_input_as_handled()

    if state.tool != DISABLED:
      if event.is_action_pressed("toggle_code_mode"):
        if state.tool != CODE_MODE:
          if state.tool in state.tools:
            self.last_tool = state.tool
          state.select_tool CODE_MODE
        else:
          state.select_tool self.last_tool
      elif event.is_action_pressed("mode_1"):
        state.select_tool CODE_MODE
      elif event.is_action_pressed("mode_2"):
        state.select_tool BLUE_BLOCK
      elif event.is_action_pressed("mode_3"):
        state.select_tool RED_BLOCK
      elif event.is_action_pressed("mode_4"):
        state.select_tool GREEN_BLOCK
      elif event.is_action_pressed("mode_5"):
        state.select_tool BLACK_BLOCK
      elif event.is_action_pressed("mode_6"):
        state.select_tool WHITE_BLOCK
      elif event.is_action_pressed("mode_7"):
        state.select_tool BROWN_BLOCK
      elif event.is_action_pressed("mode_8"):
        state.select_tool PLACE_BOT

  method on_meta_clicked(url: string) =
    if url.starts_with("nim://"):
      assert ?state.open_sign
      state.open_sign.owner.eval = url[6 ..^ 1]
    elif url.starts_with("thing://"):
      let id = url[7 ..^ 1]
      for thing in state.things:
        if thing.id == id:
          state.open_thing = thing
          return
      logger("err", \"Unable to open thing {id}")
    elif shell_open(url) != godotcoretypes.Error.OK:
      logger("err", \"Unable to open url {url}")
