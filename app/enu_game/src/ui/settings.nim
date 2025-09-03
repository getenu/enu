import std/[algorithm, math, os, monotimes, times, tables]
import gdext
import gdext/classes/[
  gdpanelcontainer, gdoptionbutton, gdlineedit, gdmargincontainer, gdtween,
  gdinputevent, gdscenetree, gdvseparator, gdviewport, gdgridcontainer,
  gdbutton, gdlabel, gdcontainer, gdinputeventjoypadbutton
]
import core, gdutils, models/[colors, serializers]

type
  WindowState = enum
    None
    Closed
    NewLevel
    Opened

const
  transition = 3  # TRANS_EXPO equivalent for Godot 4 Tween
  check = " ✓ "
  blank = "   "

type Settings* {.gdsync.} = ptr object of PanelContainer
  environments, colors, levels: OptionButton
  megapixels, font_size, toolbar_size, server_address, level_name: LineEdit
  megapixels_up, megapixels_down, font_size_up, font_size_down,
    toolbar_size_up, toolbar_size_down, switch_level, full_screen, run_server,
    connect, close, save, cancel: Button
  remote_container, main_container, new_level_container, row_container, window:
    Container
  settings_container: GridContainer
  left_separator, right_separator: VSeparator
  repeat_timers: Table[string, MonoTime]
  size_timer: MonoTime
  tween: Tween
  separation: int
  action_steps: seq[proc() {.gcsafe.}]
  state: WindowState

proc update_values(self: Settings) =
  let full_screen_label = self.find_child("FullScreenLabel", false, false).as(Label)
  if not full_screen_label.is_nil():
    full_screen_label.set_visible(host_os != "ios")
  self.full_screen.set_visible(host_os != "ios")

  self.megapixels.set_text(&"{state.config.megapixels:.2f}")
  self.font_size.set_text($state.config.font_size)
  self.toolbar_size.set_text($int(state.config.toolbar_size))
  self.full_screen.set_text(if state.config.full_screen: check else: blank)
  self.environments.select(state.config.environment)

  let level_label = self.find_child("LevelLabel", false, false).as(Label)
  if not level_label.is_nil():
    if ?state.config.connect_address:
      level_label.add_theme_color_override("font_color", ir_black[Comment])
      self.levels.set_disabled(true)
    else:
      level_label.add_theme_color_override("font_color", ir_black[Normal])
      self.levels.set_disabled(false)
      self.levels.select(state.config.level)

  if ?state.config.connect_address:
    self.server_address.set_text(state.config.connect_address)
    self.server_address.set_editable(false)
    self.connect.set_text("Disconnect")
  else:
    self.server_address.set_editable(true)
    self.connect.set_text("Connect")

proc update_level_list(self: Settings) =
  self.levels.clear()
  if not ?state.config.connect_address:
    self.levels.add_item("New...")
    for file in walk_dirs(state.config.world_dir / "*"):
      let world = file.split_file.name
      if world != "backups":
        self.levels.add_item(world)

method ready*(self: Settings) {.gdsync.} =
  print("[UI] Settings ready - initializing configuration panel")

  self.size_timer = MonoTime.high
  self.state = None

  # Initialize all UI components
  self.environments = self.find_child("Environments").as(OptionButton)
  self.colors = self.find_child("PlayerColors").as(OptionButton)
  self.levels = self.find_child("Levels").as(OptionButton)
  self.megapixels = self.find_child("Megapixels").as(LineEdit)
  self.font_size = self.find_child("FontSize").as(LineEdit)
  self.toolbar_size = self.find_child("ToolbarSize").as(LineEdit)
  self.server_address = self.find_child("ServerAddress").as(LineEdit)
  self.level_name = self.find_child("LevelName").as(LineEdit)
  self.megapixels_up = self.find_child("MegapixelsUp").as(Button)
  self.megapixels_down = self.find_child("MegapixelsDown").as(Button)
  self.font_size_up = self.find_child("FontSizeUp").as(Button)
  self.font_size_down = self.find_child("FontSizeDown").as(Button)
  self.toolbar_size_up = self.find_child("ToolbarSizeUp").as(Button)
  self.toolbar_size_down = self.find_child("ToolbarSizeDown").as(Button)
  self.full_screen = self.find_child("FullScreen").as(Button)
  self.run_server = self.find_child("RunServer").as(Button)
  self.connect = self.find_child("Connect").as(Button)
  self.save = self.find_child("Save").as(Button)
  self.cancel = self.find_child("Cancel", false, false).as(Button)
  self.remote_container = self.find_child("RemoteContainer", false, false).as(Container)
  self.main_container = self.find_child("MainContainer", false, false).as(Container)
  self.new_level_container = self.find_child("NewLevelContainer", false, false).as(Container)
  self.row_container = self.find_child("RowContainer", false, false).as(Container)
  self.settings_container = self.find_child("SettingsContainer", false, false).as(GridContainer)
  self.window = self.find_child("Window", false, false).as(Container)
  self.tween = self.find_child("Tween", false, false).as(Tween)
  self.close = self.find_child("Close", false, false).as(Button)
  self.left_separator = self.find_child("LeftSeparator", false, false).as(VSeparator)
  self.right_separator = self.find_child("RightSeparator", false, false).as(VSeparator)

  # Check for nil components
  let components = [
    ("environments", not self.environments.is_nil()),
    ("colors", not self.colors.is_nil()),
    ("levels", not self.levels.is_nil()),
    ("settings_container", not self.settings_container.is_nil()),
    ("window", not self.window.is_nil()),
    ("tween", not self.tween.is_nil())
  ]

  for (name, exists) in components:
    if not exists:
      print("[UI] ✗ Settings component not found: ", name)

  if not self.row_container.is_nil():
    # GD4: Get separation from theme instead of constants
    self.separation = 4  # Default separation, TODO: get from theme

  # Populate environments dropdown
  if not self.environments.is_nil():
    self.environments.add_item("default")
    for env in environments.keys.to_seq.sorted:
      if env notin ["default", "none"]:
        self.environments.add_item(env)
    self.environments.add_item("none")

  # Populate colors dropdown
  if not self.colors.is_nil():
    var add_hex = true
    for color in Colors:
      if color != Eraser:
        self.colors.add_item($color)
        if state.config.player_color == action_colors[color]:
          add_hex = false
          self.colors.select(self.colors.get_item_count() - 1)
    if add_hex:
      self.colors.add_item(state.config.player_color.to_html_hex)
      self.colors.select(self.colors.get_item_count() - 1)

  # TODO: Set up signal connections for Godot 4
  # GD4: Signal binding needs to be updated for gdext patterns
  print("[UI] ✗ Settings signal binding not yet implemented for Godot 4")

  # TODO: Set up state watching
  # GD4: State change watching needs to be updated
  print("[UI] ✗ Settings state watching not yet implemented for Godot 4")

  self.update_level_list()
  self.update_values()

  if SettingsVisible notin state.local_flags:
    if not self.window.is_nil():
      self.window.set_modulate(gdext.color(1.0, 1.0, 1.0, 0.0))  # Transparent
      # TODO: Implement window positioning

  print("[UI] Settings initialized - configuration panel ready")
