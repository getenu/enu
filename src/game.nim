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
    scroll_container, voxel_server, world_environment, camera,
  ]

import ui/virtual_joystick
import
  core, types, gdutils, controllers, models/[serializers, units, colors, builds]

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

var environment_cache {.threadvar.}: Table[string, Environment]

gdobj Game of Node:
  var
    reticle: Control
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
    mcp_camera_node: Camera
    mcp_viewport_node: Viewport

  method process*(delta: float) =
    Ed.thread_ctx.tick
    inc state.frame_count

    let time = get_mono_time()
    when defined(metrics):
      if self.update_metrics_at < time:
        update_thread_metrics()
        self.update_metrics_at = time + 10.seconds

    if state.config.full_screen != is_window_fullscreen():
      state.config_value.value:
        full_screen = not state.config.full_Screen

    if state.config.show_stats:
      let fps = get_monitor(TIME_FPS)

      let vram = get_monitor(RENDER_VIDEO_MEM_USED)
      var unit_count = 0
      state.units.value.walk_tree proc(unit: Unit) =
        inc unit_count

      self.stats.text =
        \"""
        FPS: {fps}
        scale_factor: {state.scale_factor}
        vram: {vram}
        units: {unit_count}
        zen objects: {Ed.thread_ctx.len}
        level: {state.level_name}
        {get_network_stats()}
        {get_stats()}
        """
    state.voxel_tasks =
      parse_int($get_stats()["tasks"].as_dictionary["main_thread"])

    if time > self.rescale_at:
      self.rescale_at = MonoTime.high
      self.rescale()

    if time > self.force_quit_at:
      state.pop_flag QUITTING

    if SCENE_READY notin state.local_flags:
      state.push_flag SCENE_READY

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
    let work_dir =
      if (let i = args.find("--temp-workdir"); i) > -1:
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

    if (let i = args.find("--connect"); i) > -1 and args.len > i + 1:
      connect_address_override = args[i + 1]
      args.delete(i .. i + 1)
    if (let i = args.find("--listen"); i) > -1:
      if args.len > i + 1:
        listen_address_override = args[i + 1]
        args.delete(i .. i + 1)
      else:
        listen_address_override = "0.0.0.0"
        args.delete(i)
    if (let i = args.find("--level-dir"); i) > -1 and args.len > i + 1:
      level_dir_override = args[i + 1]
      args.delete(i .. i + 1)
    if (let i = args.find("--enu-test"); i) > -1:
      test_mode = true
      args.delete(i)
    if (let i = args.find("--level"); i) > -1:
      let parts = args[i + 1].split("/")
      uc.world = some(parts[0])
      uc.level = some(parts[1])
      args.delete(i .. i + 1)

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
      let vmlib = join_path(get_executable_path().parent_dir(), "vmlib")
    else:
      # state.push_flag TOUCH_CONTROLS
      let vmlib =
        join_path(get_executable_path().parent_dir(), "..", "..", "..", "vmlib")

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
      lib_dir = vmlib
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

      state.config_value.value:
        level = new_level
        world = new_world
        world_dir = final_world_dir
        level_dir = final_level_dir

    if test_mode:
      notice "test mode enabled"
      state.push_flag TEST_MODE

    state.set_flag(GOD, uc.god_mode ||= false)

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
          lib_dir = join_path(exe_dir.parent_dir, "Resources", "vmlib")
      elif host_os == "windows":
        state.config_value.value:
          lib_dir = join_path(exe_dir, "vmlib")
      elif host_os == "linux":
        state.config_value.value:
          lib_dir = join_path(exe_dir.parent_dir, "lib", "vmlib")

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
      self.mcp_viewport_node = gdnew[Viewport]()
      self.mcp_viewport_node.name = "McpViewport"
      self.mcp_viewport_node.size = vec2(640, 360)
      self.mcp_viewport_node.render_target_update_mode = UPDATE_ALWAYS
      self.add_child(self.mcp_viewport_node)
      self.mcp_viewport_node.world = self.scaled_viewport.find_world()
      self.mcp_camera_node = gdnew[Camera]()
      self.mcp_camera_node.name = "McpCamera"
      self.mcp_viewport_node.add_child(self.mcp_camera_node)
      self.mcp_camera_node.make_current()
      state.mcp_camera = self.mcp_camera_node
      state.mcp_viewport = self.mcp_viewport_node
      state.screenshot_viewport = self.scaled_viewport

      self.bind_signals(self.get_viewport(), "size_changed")
      self.bind_signals(self.get_tree(), "global_menu_action")
      assert not self.scaled_viewport.is_nil
      self.get_tree().auto_accept_quit = false
      self.set_font_size(state.config.font_size)
      info "loading environment", env = state.config.environment
      self.load_environment(state.config.environment)
      info "config", config = state.config
      self.reticle = self.find_node("Reticle").as(Control)
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
        var ev = gdnew[InputEventAction]()
        ev.action = state.queued_action
        ev.pressed = true
        state.queued_action = ""
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
          self.last_tool = state.tool
          state.tool = CODE_MODE
        else:
          state.tool = self.last_tool
      elif event.is_action_pressed("mode_1"):
        state.tool = CODE_MODE
      elif event.is_action_pressed("mode_2"):
        state.tool = BLUE_BLOCK
      elif event.is_action_pressed("mode_3"):
        state.tool = RED_BLOCK
      elif event.is_action_pressed("mode_4"):
        state.tool = GREEN_BLOCK
      elif event.is_action_pressed("mode_5"):
        state.tool = BLACK_BLOCK
      elif event.is_action_pressed("mode_6"):
        state.tool = WHITE_BLOCK
      elif event.is_action_pressed("mode_7"):
        state.tool = BROWN_BLOCK
      elif event.is_action_pressed("mode_8"):
        state.tool = PLACE_BOT

  method on_meta_clicked(url: string) =
    if url.starts_with("nim://"):
      assert ?state.open_sign
      state.open_sign.owner.eval = url[6 ..^ 1]
    elif url.starts_with("unit://"):
      let id = url[7 ..^ 1]
      for unit in state.units:
        if unit.id == id:
          state.open_unit = unit
          return
      logger("err", \"Unable to open unit {id}")
    elif shell_open(url) != godotcoretypes.Error.OK:
      logger("err", \"Unable to open url {url}")
