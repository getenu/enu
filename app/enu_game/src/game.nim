import std/[monotimes, os, json, math, random, net]
import pkg/[metrics, metrics/stdlib_httpserver]
from dotenv import nil
import gdext
import
  gdext/classes/[
    gdinput, gdinputevent, gdos, gdnode, gdscenetree, gdpackedscene, gdcontrol,
    gdviewport, gdperformance, gdlabel, gdtheme, gdfont, gdresourceloader,
    gdprojectsettings, gdinputmap, gdinputeventaction, gdinputeventkey,
    gdinputeventmousebutton, gdscrollcontainer, gdenvironment, gdworldenvironment,
    gddisplayserver, gdviewport, gdsubviewport,
  ]

import ui/virtual_joystick
import core, types, controllers, models/[serializers, units, colors, states], gdutils

if file_exists(".env"):
  dotenv.overload()

when defined(metrics):
  set_system_metrics_automatic_update(false)

ZenContext.init_metrics "main", "worker"

# saved state when restarting worker thread
const savable_flags =
  {ConsoleVisible, MouseCaptured, Flying, God, AltWalkSpeed, AltFlySpeed}

var environment_cache {.threadvar.}: Table[string, gdref Environment]

type Game* {.gdsync.} =
  ptr object of Node
    reticle: Control
    scaled_viewport: Viewport
    triggered: bool
    saved_mouse_captured_state: bool
    stats: Label
    last_tool: Tools
    saved_mouse_position: Vector2
    rescale_at: MonoTime
    update_metrics_at: MonoTime
    force_quit_at: MonoTime
    node_controller: NodeController
    script_controller: ScriptController
    left_stick: VirtualJoystick
    verify_mode: bool

# GD4: Basic initialization moved to main init_game function

proc rescale*(self: Game) =
  discard
  # GD4: fixme
  # let vp = self.get_viewport().size
  # let megapixels =
  #   if ?state.config.megapixels_override:
  #     state.config.megapixels_override
  #   else:
  #     state.config.megapixels
  # state.scale_factor = sqrt(megapixels * 1_000_000.0 / (vp.x * vp.y))

  # self.scaled_viewport.size = vp * state.scale_factor
  # self.scaled_viewport.get_texture.flags = if megapixels >= 1.0: FLAG_FILTER else: 0

  #info "Rescaled viewport", size = self.scaled_viewport.size

method process*(self: Game, delta: float) {.gdsync.} =
  Zen.thread_ctx.boop
  inc state.frame_count
  let time = get_mono_time()
  when defined(metrics):
    if self.update_metrics_at < time:
      update_thread_metrics()
      self.update_metrics_at = time + 10.seconds

  if state.config.full_screen !=
      (DisplayServer.window_get_mode() == windowModeFullscreen):
    state.config_value.value:
      full_screen = not state.config.full_Screen

  if state.config.show_stats:
    let fps = Performance.get_monitor(timeFps)

    let vram = Performance.get_monitor(renderVideoMemUsed)
    var unit_count = 0
    state.units.value.walk_tree proc(unit: Unit) =
      inc unit_count

    self.stats.text =
      """
      FPS: {fps}
      scale_factor: {state.scale_factor}
      vram: {vram}
      units: {unit_count}
      zen objects: {Zen.thread_ctx.len}
      level: {state.level_name}
      # {get_stats()} # TODO: Fix for Godot 4
      """
  # TODO: Fix for Godot 4
  # state.voxel_tasks =
  #   parse_int($get_stats()["tasks"].as_dictionary()["main_thread"])
  state.voxel_tasks = 0

  if time > self.rescale_at:
    self.rescale_at = MonoTime.high
    rescale(self)

  if time > self.force_quit_at:
    state.pop_flag Quitting

  if SceneReady notin state.local_flags:
    state.push_flag SceneReady

# GD4
# method notification*(self: Game, what: int) {.gdsync.} =
#   if what == main_loop.NOTIFICATION_WM_QUIT_REQUEST:
#     state.push_flag Quitting

#   if what == main_loop.NOTIFICATION_WM_ABOUT:
#     alert "Enu {enu_version}\n\n© 2025 Scott Wadden", "Enu"

# GD4: TODO - Fix platform-specific input actions for Godot 4
proc add_platform_input_actions(self: Game) =
  discard
  # let suffix = "." & host_os
  # for action in InputMap.get_actions():
  #   let action = action.as_string()
  #   if suffix in action:
  #     let name = action.replace(suffix, "")
  #     if InputMap.has_action(name):
  #       InputMap.erase_action(name)
  #     InputMap.add_action(name)
  #     for event in InputMap.get_action_list(action):
  #       let event = event.as_object(InputEvent)
  #       InputMap.action_add_event(name, event)
  #     InputMap.erase_action(action)

method onInit*(self: Game) {.gdsync.} =
  # Basic field initialization
  self.triggered = false
  self.saved_mouse_captured_state = false
  self.last_tool = BlueBlock
  self.rescale_at = get_mono_time()
  self.update_metrics_at = get_mono_time()
  self.force_quit_at = MonoTime.high
  self.verify_mode = false
  self.process_priority = -100

  # GD4: TODO - Fix screen scale detection for Godot 4
  let screen_scale = 1.0
  # if host_os == "macos":
  #   get_screen_scale(-1)
  # else:
  #   get_screen_dpi(-1).float / 96.0

  var initial_user_config = load_user_config($OS.get_user_data_dir())

  Zen.thread_ctx = ZenContext.init(
    id = "main-{generate_id()}",
    chan_size = 2000,
    buffer = true,
    label = "main",
    max_recv_duration = (1.0 / 30.0).seconds,
  )

  state = GameState.init
  state.nodes.game = self

  var uc = initial_user_config
  assert not state.is_nil

  random.randomize()

  var args = OS.get_cmdline_args().to_seq.mapIt($it) # Convert to Nim strings

  var connect_address = ""
  var listen_address = ""
  var verify_mode = false
  if (let i = args.find("--connect"); i) > -1 and args.len > i + 1:
    connect_address = args[i + 1]
    args.delete(i .. i + 1)
  if (let i = args.find("--listen"); i) > -1:
    if args.len > i + 1:
      listen_address = args[i + 1]
      args.delete(i .. i + 1)
    else:
      listen_address = "0.0.0.0"
      args.delete(i)
  if (let i = args.find("--verify"); i) > -1:
    verify_mode = true
    args.delete(i)

  if ?($OS.get_environment("ENU_LISTEN_ADDRESS")) and not ?listen_address:
    listen_address = $OS.get_environment("ENU_LISTEN_ADDRESS")
  if ?($OS.get_environment("ENU_CONNECT_ADDRESS")) and not ?connect_address:
    connect_address = $OS.get_environment("ENU_CONNECT_ADDRESS")
  if ?listen_address and ?connect_address:
    fail "Cannot set both ENU_LISTEN_ADDRESS and ENU_CONNECT_ADDRESS"

  if ?saved_state.connect_address:
    connect_address = saved_state.connect_address

  # GD4: TODO - Fix global menu for Godot 4
  # if host_os == "macosx" and not saved_state.restarting:
  #   global_menu_add_item("Help", "Documentation", "help".to_variant, "".to_variant)
  #   global_menu_add_item("Help", "Web Site", "site".to_variant, "".to_variant)
  #   if connect_address == "":
  #     global_menu_add_separator("Help")
  #     global_menu_add_item(
  #       "Help", "Launch Tutorial", "tutorial".to_variant, "".to_variant
  #     )

  when host_os == "ios":
    state.push_flag TouchControls
    let vmlib = join_path($OS.get_executable_path().get_base_dir(), "vmlib")
  else:
    # state.push_flag TouchControls
    let vmlib =
      join_path($OS.get_executable_path().get_base_dir(), "..", "..", "..", "vmlib")

  state.config_value.value:
    screen_scale = screen_scale
    work_dir = $OS.get_user_data_dir()
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
    player_color = uc.player_color ||= colortools.color(rand(1.0), rand(1.0), rand(1.0))
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

  if ?listen_address:
    state.config_value.value:
      listen_address = listen_address

  if ?connect_address:
    state.config_value.value:
      connect_address = connect_address

  state.set_flag(God, uc.god_mode ||= false)

  DisplayServer.window_set_mode(
    if state.config.full_screen: windowModeFullscreen else: windowModeWindowed
  )
  when defined(metrics):
    let metrics_port =
      if ?($OS.get_environment("ENU_METRICS_PORT")):
        ($OS.get_environment("ENU_METRICS_PORT")).parse_int
      else:
        8000

    {.cast(gcsafe).}:
      start_metrics_http_server("0.0.0.0", Port(metrics_port))

  self.add_platform_input_actions()

  when defined(dist):
    let exe_dir = $OS.get_executable_path().get_base_dir()
    if host_os == "macosx":
      state.config_value.value:
        lib_dir = join_path(exe_dir.parent_dir, "Resources", "vmlib")
    elif host_os == "windows":
      state.config_value.value:
        lib_dir = join_path(exe_dir, "vmlib")
    elif host_os == "linux":
      state.config_value.value:
        lib_dir = join_path(exe_dir.parent_dir, "lib", "vmlib")

  self.verify_mode = verify_mode
  self.node_controller = NodeController.init
  self.script_controller = ScriptController.init

  save_user_config(uc)

# GD4: TODO - Fix panel width calculation for Godot 4
proc set_panel_width(self: Game) =
  discard
  # let
  #   theme = self.find_child("LeftPanel").as(Container).theme
  #   mono_font = theme.get_font("font", "MonoButton").as(DynamicFont)
  #   font_width = mono_font.get_string_size(" ".repeat(34)).x
  #   viewport_width = self.get_viewport().size.x
  #
  # if font_width > viewport_width / 2.0:
  #   state.push_flag FullWidthPanels
  # else:
  #   state.pop_flag FullWidthPanels

# GD4: TODO - Fix font size handling for Godot 4
proc set_font_size(self: Game, size: int) =
  if state.config.font_size != size:
    var user_config = load_user_config()
    state.config_value.value:
      font_size = size
  # Complex font handling commented out for initial port
  # let
  #   theme = find("LeftPanel", Container).theme
  #   font = theme.default_font.as(DynamicFont)
  #   bold_font = theme.get_font("bold_font", "RichTextLabel").as(DynamicFont)
  #   icon_font = theme.get_font("font", "IconButton").as(DynamicFont)
  #   mono_font = theme.get_font("font", "MonoButton").as(DynamicFont)
  #   label_font = theme.get_font("font", "Label").as(DynamicFont)
  #   normal_font = theme.get_font("font", "LineEdit").as(DynamicFont)
  #
  # font.size = (size.float * state.config.screen_scale).int
  # bold_font.size = font.size
  # icon_font.size = font.size
  # mono_font.size = font.size
  # label_font.size = font.size
  # normal_font.size = font.size

  set_panel_width(self)

# GD4: TODO - Fix GUI input handling for Godot 4
# method on_gui_input*(self: Game, event: InputEvent, name: string) {.gdsync.} =
#   if event of InputEventMouseButton:
#     case name
#     of "Editor":
#       debug "pushing EditorFocused", topics = "state"
#       state.push_flag EditorFocused
#     of "Console":
#       debug "pushing ConsoleFocused", topics = "state"
#       state.push_flag ConsoleFocused
#     of "Settings":
#       debug "pushing SettingsFocused", topics = "state"
#       state.push_flag SettingsFocused
#     of "RightPanel":
#       debug "pushing DocsFocused", topics = "state"
#       state.push_flag DocsFocused
#     else:
#       warn "Couldn't focus control", name

proc load_environment(self: Game, environment: string) =
  let env =
    state.nodes.game.find_child("Level").get_node("WorldEnvironment") as WorldEnvironment
  if environment notin environment_cache:
    let res = &"res://environments/{environment}.tres"

    var environment_res: Environment = nil
    if environment != "none":
      environment_res = cast[Environment](ResourceLoader.load(res))
      if environment_res.is_nil:
        logger("err", &"Environment {environment} not found")
        return
    environment_cache[environment] = cast[gdref Environment](environment_res)
  env.set_environment(environment_cache[environment])
  state.config_value.value:
    megapixels_override = environments[environment]
  info "Changed game mode", environment

proc run_verification*(self: Game) =
  info "[VERIFY] Enu verification starting..."

  # Test basic systems and configuration
  info "[VERIFY] Systems initialized",
    vm = ?self.script_controller,
    node_controller = not self.node_controller.is_nil,
    scene_system = ?state.nodes,
    world = state.config.world,
    level = state.config.level,
    work_dir = state.config.work_dir,
    lib_dir = state.config.lib_dir

  # Test VM context and paths
  let world_path = join_path(state.config.work_dir, state.config.world)
  let level_path = join_path(world_path, state.config.level)

  info "[VERIFY] System status",
    vm_context = not Zen.thread_ctx.is_nil,
    world_exists = dir_exists(world_path),
    level_exists = dir_exists(level_path),
    world_path = world_path,
    level_path = level_path

  # Test basic scene tree
  let viewport = self.get_viewport()
  let scene_tree =
    if not viewport.is_nil:
      self.get_tree()
    else:
      nil

  info "[VERIFY] Scene tree status",
    viewport_ok = not viewport.is_nil, scene_tree_ok = not scene_tree.is_nil

  info "[VERIFY] Verification completed - setting quit flag"
  state.push_flag(Quitting)

method ready*(self: Game) {.gdsync.} =
  echo ?state
  echo ?state.nodes
  echo not state.nodes.data.is_nil
  echo not state.nodes.game.find_child("Level").is_nil
  echo not state.nodes.game.find_child("Level").get_node("data").is_nil

  state.nodes.data = state.nodes.game.find_child("Level").get_node("data")
  assert not state.nodes.data.is_nil
  # GD4: fix scaled_viewport
  # self.scaled_viewport = self.get_node("ViewportContainer/Viewport") as Viewport

  self.bind_signals(self.get_viewport(), "size_changed")
  self.bind_signals(self.get_tree(), "global_menu_action")
  # assert not self.scaled_viewport.is_nil
  self.get_tree().auto_accept_quit = false
  self.set_font_size(state.config.font_size)
  self.load_environment(state.config.environment)
  info "config", config = state.config
  self.reticle = self.find_child("Reticle").as(Control)
  self.stats = self.find_child("stats").as(Label)
  self.left_stick = find("LeftStick", VirtualJoystick)
  # self.stats.visible = state.config.show_stats

  state.config_value.changes:
    if change.item.full_screen != state.config.full_screen:
      DisplayServer.window_set_mode(
        if state.config.full_screen: windowModeFullscreen else: windowModeWindowed
      )
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
      discard self.get_tree().reload_current_scene()

    if Connecting.added:
      state.status_message =
        """
          # Connecting...

          Trying to connect to {state.config.connect_address}.
          """
    elif Connecting.removed:
      state.status_message = ""

    if MouseCaptured.added:
      let center = self.get_viewport().get_visible_rect().size * 0.5
      self.saved_mouse_position = self.get_viewport().get_mouse_position()
      Input.warp_mouse(center)
      Input.set_mouse_mode(mouseModeCaptured)
    elif MouseCaptured.removed:
      Input.set_mouse_mode(mouseModeVisible)
      Input.warp_mouse(self.saved_mouse_position)

    if ReticleVisible.added:
      self.reticle.visible = true
    elif ReticleVisible.removed:
      self.reticle.visible = false

  if TouchControls notin state.local_flags:
    state.push_flag MouseCaptured
  state.push_flag ViewportFocused

  # GD4: TODO - Fix InputEventAction creation for Godot 4
  # state.queued_action_value.changes:
  #   if added and change.item != "":
  #     var ev = gdnew[InputEventAction]()
  #     ev.action = state.queued_action
  #     ev.pressed = true
  #     state.queued_action = ""
  #     parse_input_event(ev)

  # Run verification mode if requested
  if self.verify_mode:
    self.run_verification()

proc on_size_changed(self: Game) {.gdsync.} =
  self.rescale_at = get_mono_time()
  self.set_panel_width()

proc on_global_menu_action(self: Game, action: string, id: string) {.gdsync.} =
  if action == "help":
    discard OS.shell_open("http://getenu.com/docs/intro.html")
  elif action == "site":
    discard OS.shell_open("http://getenu.com")
  elif action == "settings":
    state.push_flag SettingsVisible
  elif action == "openurl":
    logger("info", "Open URL: {id}")
  elif action == "tutorial":
    state.config_value.value:
      level_dir = ""
    state.player.transform = Transform3D.init(origin = vector3(0, 2, 0))
    state.player.rotation = 0
    change_loaded_level("tutorial-1", "tutorial")
  else:
    warn "Unknown action", action, id

proc switch_world(self: Game, diff: int) =
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

method unhandled_input*(self: Game, event: InputEvent) {.gdsync.} =
  if event of InputEventKey:
    let event = InputEventKey(event)
    # GD4: TODO - Fix alt key detection (raw_code was enu-specific Godot 3 addition)
    # Left alt support. raw_code is an enu specific addition
    # if (host_os == "macosx" and event.raw_code == 58) or
    #     (host_os == "windows" and event.raw_code == 56) or
    #     (host_os == "linux" and event.raw_code == 65513):
    #   if event.pressed:
    #     state.push_flag CommandMode
    #   else:
    #     state.pop_flag CommandMode

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
    event.as(InputEventKey).keycode == keyEnter
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
    self.get_viewport().set_input_as_handled()
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
      self.get_viewport().set_input_as_handled()

  if state.current_tool != Disabled:
    if event.is_action_pressed("toggle_code_mode"):
      if state.current_tool != CodeMode:
        self.last_tool = state.current_tool
        state.current_tool = CodeMode
      else:
        state.current_tool = self.last_tool
    elif event.is_action_pressed("mode_1"):
      state.current_tool = CodeMode
    elif event.is_action_pressed("mode_2"):
      state.current_tool = BlueBlock
    elif event.is_action_pressed("mode_3"):
      state.current_tool = RedBlock
    elif event.is_action_pressed("mode_4"):
      state.current_tool = GreenBlock
    elif event.is_action_pressed("mode_5"):
      state.current_tool = BlackBlock
    elif event.is_action_pressed("mode_6"):
      state.current_tool = WhiteBlock
    elif event.is_action_pressed("mode_7"):
      state.current_tool = BrownBlock
    elif event.is_action_pressed("mode_8"):
      state.current_tool = PlaceBot

proc on_meta_clicked(self: Game, url: string) {.gdsync.} =
  if url.starts_with("nim://"):
    assert ?state.open_sign
    state.open_sign.owner.eval = url[6 ..^ 1]
  elif url.starts_with("unit://"):
    let id = url[7 ..^ 1]
    for unit in state.units:
      if unit.id == id:
        state.open_unit = unit
        return
    logger("err", "Unable to open unit {id}")
  elif OS.shell_open(url) != ok:
    logger("err", "Unable to open url {url}")
