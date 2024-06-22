import std/[monotimes, os, json, math, random, net]
import pkg/[godot, metrics, metrics/stdlib_httpserver]
from dotenv import nil
import
  godotapi/[
    input, input_event, gd_os, node, scene_tree, packed_scene, sprite, control,
    viewport, viewport_texture, performance, label, theme, dynamic_font,
    resource_loader, main_loop, project_settings, input_map, input_event_action,
    input_event_key, input_event, global_constants, scroll_container,
    voxel_server, world_environment
  ]

import ui/virtual_joystick
import core, types, gdutils, controllers, models/[serializers, units, colors]

if file_exists(".env"):
  dotenv.overload()

when defined(metrics):
  set_system_metrics_automatic_update(false)

ZenContext.init_metrics "main", "worker"

# saved state when restarting worker thread
const savable_flags = {
  ConsoleVisible, MouseCaptured, Flying, God, AltWalkSpeed, AltFlySpeed
}

var environment_cache {.threadvar.}: Table[string, Environment]

gdobj Game of Node:
  var
    reticle: Control
    scaled_viewport: Viewport
    triggered = false
    saved_mouse_captured_state = false
    stats: Label
    last_tool = BlueBlock
    saved_mouse_position: Vector2
    rescale_at = get_mono_time()
    update_metrics_at = get_mono_time()
    force_quit_at = MonoTime.high
    node_controller: NodeController
    script_controller: ScriptController
    left_stick: VirtualJoystick

  method process*(delta: float) =
    Zen.thread_ctx.boop
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
        zen objects: {Zen.thread_ctx.len}
        level: {state.level_name}
        {get_stats()}
        """
    state.voxel_tasks =
      parse_int($get_stats()["tasks"].as_dictionary["main_thread"])

    if time > self.rescale_at:
      self.rescale_at = MonoTime.high
      self.rescale()

    if time > self.force_quit_at:
      state.pop_flag Quitting

    if SceneReady notin state.local_flags:
      state.push_flag SceneReady

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
      state.push_flag Quitting

    if what == main_loop.NOTIFICATION_WM_ABOUT:
      alert \"Enu {enu_version}\n\n© 2024 Scott Wadden", "Enu"

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
    self.process_priority = -100

    let screen_scale =
      if host_os == "macos":
        get_screen_scale(-1)
      else:
        get_screen_dpi(-1).float / 96.0

    var initial_user_config = load_user_config(get_user_data_dir())

    Zen.thread_ctx = ZenContext.init(
      id = \"main-{generate_id()}",
      chan_size = 2000,
      buffer = true,
      label = "main",
    )

    state = GameState.init
    state.nodes.game = self

    var uc = initial_user_config
    assert not state.is_nil

    randomize()

    var connect_address = ""
    var listen_address = ""

    if ?get_env("ENU_LISTEN_ADDRESS") and ?get_env("ENU_CONNECT_ADDRESS"):
      fail "Cannot set both ENU_LISTEN_ADDRESS and ENU_CONNECT_ADDRESS"
    elif ?get_env("ENU_LISTEN_ADDRESS"):
      listen_address = get_env("ENU_LISTEN_ADDRESS")
      connect_address = ""
    elif ?get_env("ENU_CONNECT_ADDRESS"):
      connect_address = get_env("ENU_CONNECT_ADDRESS")
      listen_address = ""

    if ?saved_state.connect_address:
      connect_address = saved_state.connect_address

    if host_os == "macosx" and not saved_state.restarting:
      global_menu_add_item(
        "Help", "Documentation", "help".to_variant, "".to_variant
      )
      global_menu_add_item("Help", "Web Site", "site".to_variant, "".to_variant)
      if connect_address == "":
        global_menu_add_separator("Help")
        global_menu_add_item(
          "Help", "Launch Tutorial", "tutorial".to_variant, "".to_variant
        )

    when host_os == "ios":
      state.push_flag TouchControls
      let vmlib = join_path(get_executable_path().parent_dir(), "vmlib")
    else:
      let vmlib =
        join_path(get_executable_path().parent_dir(), "..", "..", "..", "vmlib")

    state.config_value.value:
      screen_scale = screen_scale
      work_dir = get_user_data_dir()
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
      connect_address = connect_address
      listen_address = listen_address
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

    state.set_flag(God, uc.god_mode ||= false)

    set_window_fullscreen state.config.full_screen
    when defined(metrics):
      let metrics_port =
        if ?get_env("ENU_METRICS_PORT"):
          get_env("ENU_METRICS_PORT").parse_int
        else:
          8000

      {.cast(gcsafe).}:
        start_metrics_http_server("0.0.0.0", Port(metrics_port))

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

  proc set_font_size(size: int) =
    if state.config.font_size != size:
      var user_config = load_user_config()
      state.config_value.value:
        font_size = size

    let
      theme_holder = self.find_node("LeftPanel").as(Container)
      theme = theme_holder.theme
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
    theme_holder.theme = theme

  method on_gui_input*(event: InputEvent, name: string) =
    if event of InputEventMouseButton:
      case name
      of "Editor":
        debug "pushing EditorFocused", topics = "state"
        state.push_flag EditorFocused
      of "Console":
        debug "pushing ConsoleFocused", topics = "state"
        state.push_flag ConsoleFocused
      of "Settings":
        debug "pushing SettingsFocused", topics = "state"
        state.push_flag SettingsFocused
      of "RightPanel":
        debug "pushing DocsFocused", topics = "state"
        state.push_flag DocsFocused
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
    state.nodes.data = state.nodes.game.find_node("Level").get_node("data")
    assert not state.nodes.data.is_nil
    self.scaled_viewport =
      self.get_node("ViewportContainer/Viewport") as Viewport

    self.bind_signals(self.get_viewport(), "size_changed")
    self.bind_signals(self.get_tree(), "global_menu_action")
    assert not self.scaled_viewport.is_nil
    self.get_tree().auto_accept_quit = false
    self.set_font_size(state.config.font_size)
    self.load_environment(state.config.environment)
    info "config", config = state.config
    self.reticle = self.find_node("Reticle").as(Control)
    self.stats = self.find_node("stats").as(Label)
    self.left_stick = find("LeftStick", VirtualJoystick)
    self.stats.visible = state.config.show_stats

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
      if Quitting.added:
        # We don't quit until the worker thread acks by popping the `Quitting`
        # flag, giving it a chance to save and cleanup. If the worker thread is
        # stuck, killed, or hasn't fully started because it's trying to connect
        # to a server, it won't pop the flag, so we force it after a timeout.
        self.force_quit_at = get_mono_time() + 2.seconds
      elif Quitting.removed:
        self.get_tree().quit()

      if NeedsRestart.removed:
        saved_state.transform = state.player.transform
        saved_state.rotation = state.player.rotation
        saved_state.flags = {}
        saved_state.connect_address = state.config.connect_address

        for flag in state.local_flags:
          if flag in savable_flags:
            saved_state.flags.incl(flag)

        saved_state.restarting = true
        discard self.get_tree.reload_current_scene()

      if Connecting.added:
        state.status_message =
          \"""
          # Connecting...

          Trying to connect to {state.config.connect_address}.
          """
      elif Connecting.removed:
        state.status_message = ""

      if MouseCaptured.added:
        let center = self.get_viewport().get_visible_rect().size * 0.5
        self.saved_mouse_position = self.get_viewport().get_mouse_position()
        warp_mouse_position(center)
        set_mouse_mode MOUSE_MODE_CAPTURED
      elif MouseCaptured.removed:
        set_mouse_mode MOUSE_MODE_VISIBLE
        warp_mouse_position(self.saved_mouse_position)

      if ReticleVisible.added:
        self.reticle.visible = true
      elif ReticleVisible.removed:
        self.reticle.visible = false

    if TouchControls notin state.local_flags:
      state.push_flag MouseCaptured

    state.queued_action_value.changes:
      if added and change.item != "":
        var ev = gdnew[InputEventAction]()
        ev.action = state.queued_action
        ev.pressed = true
        state.queued_action = ""
        parse_input_event(ev)

  method on_size_changed() =
    self.rescale_at = get_mono_time()

  method on_global_menu_action(action: string, id: string) =
    if action == "help":
      discard shell_open("http://getenu.com/docs/intro.html")
    elif action == "site":
      discard shell_open("http://getenu.com")
    elif action == "settings":
      state.push_flag SettingsVisible
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
          state.push_flag CommandMode
        else:
          state.pop_flag CommandMode

    if EditorVisible in state.local_flags or DocsVisible in state.local_flags or
        ConsoleVisible in state.local_flags:
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
      host_os == "windows" and CommandMode in state.local_flags and
      EditorVisible in state.local_flags and event of InputEventKey and
      event.as(InputEventKey).scancode == KEY_ENTER
    ):
      state.config_value.value:
        full_screen = not state.config.full_screen
    elif event.is_action_pressed("settings"):
      state.set_flag SettingsVisible, SettingsVisible notin state.local_flags
    elif event.is_action_pressed("next_level"):
      self.switch_world(+1)
    elif event.is_action_pressed("prev_level"):
      self.switch_world(-1)
    elif event.is_action_pressed("save_and_reload"):
      state.pop_flag Playing
      state.push_flag ResettingVM
      self.switch_world(0)
      state.pop_flag ResettingVM
      self.get_tree().set_input_as_handled()
    elif event.is_action_pressed("pause"):
      state.paused = not state.paused
    elif event.is_action_pressed("clear_console"):
      state.console.log.clear()
    elif event.is_action_pressed("toggle_console"):
      if ConsoleVisible in state.local_flags:
        state.pop_flags ConsoleVisible, ConsoleFocused
      else:
        state.push_flags ConsoleVisible, ConsoleFocused
    elif event.is_action_pressed("quit"):
      if host_os != "macosx":
        state.push_flag Quitting
    elif event.is_action_pressed("change_mode"):
      var mode = state.config.environment
      let keys = environments.keys.to_seq
      while (mode = keys.sample; mode == state.config.environment):
        discard
      state.config_value.value:
        environment = mode
    elif EditorVisible notin state.local_flags:
      if event.is_action_pressed("toggle_mouse_captured"):
        state.set_flag MouseCaptured, MouseCaptured notin state.local_flags
        self.get_tree().set_input_as_handled()

    if state.tool != Disabled:
      if event.is_action_pressed("toggle_code_mode"):
        if state.tool != CodeMode:
          self.last_tool = state.tool
          state.tool = CodeMode
        else:
          state.tool = self.last_tool
      elif event.is_action_pressed("mode_1"):
        state.tool = CodeMode
      elif event.is_action_pressed("mode_2"):
        state.tool = BlueBlock
      elif event.is_action_pressed("mode_3"):
        state.tool = RedBlock
      elif event.is_action_pressed("mode_4"):
        state.tool = GreenBlock
      elif event.is_action_pressed("mode_5"):
        state.tool = BlackBlock
      elif event.is_action_pressed("mode_6"):
        state.tool = WhiteBlock
      elif event.is_action_pressed("mode_7"):
        state.tool = BrownBlock
      elif event.is_action_pressed("mode_8"):
        state.tool = PlaceBot

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
