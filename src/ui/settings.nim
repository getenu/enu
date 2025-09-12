import std/[algorithm, math, os, monotimes, times, tables]
import gdext
import
  gdext/classes/[
    gdpanelcontainer, gdoptionbutton, gdlineedit, gdmargincontainer, gdtween,
    gdinputevent, gdscenetree, gdvseparator, gdviewport, gdgridcontainer,
    gdbutton, gdlabel, gdcontainer, gdinputeventjoypadbutton, gdbasebutton,
    gdinputeventjoypadmotion,
  ]
import core, gdutils, models/[colors, serializers]

type WindowState = enum
  None
  Closed
  NewLevel
  Opened

const
  transition = 5 # TRANS_EXPO equivalent for Godot 4 (transExpo = 5)
  ease_in_out = 2 # EASE_IN_OUT equivalent for Godot 4 (easeInOut = 2)
  check = " ✓ "
  blank = "   "

type Settings* {.gdsync.} = ptr object of Control
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
  separation: int
  action_steps: seq[proc() {.gc_safe.}]
  state: WindowState

proc update_values(self: Settings) =
  let full_screen_label = find("FullScreenLabel", Label)
  if ?full_screen_label:
    full_screen_label.set_visible(host_os != "ios")
  self.full_screen.set_visible(host_os != "ios")

  self.megapixels.set_text(&"{state.config.megapixels:.2f}")
  self.font_size.set_text($state.config.font_size)
  self.toolbar_size.set_text($int(state.config.toolbar_size))
  self.full_screen.set_text(if state.config.full_screen: check else: blank)
  self.environments.select(state.config.environment)
  let level_label = find("LevelLabel", Label)
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

proc collapsed_margin(self: Settings): int =
  -int(
    self.settings_container.get_size().y + self.remote_container.get_size().y +
      float(self.separation) * 2.0
  ) + 5

proc remote_opened_margin(self: Settings): int =
  0

proc remote_closed_margin(self: Settings): int =
  -int(self.remote_container.get_size().y + float(self.separation)) + 15

proc expanded_margin(self: Settings): int =
  result =
    if ?state.config.listen_address:
      self.remote_closed_margin
    else:
      self.remote_opened_margin

proc new_level_margin(self: Settings): int =
  int(
    self.remote_container.get_size().y + float(self.separation) +
      self.new_level_container.get_size().y / 2.0 + 10
  )

proc collapsed_new_level_margin(self: Settings): int =
  result =
    int(float(self.collapsed_margin) - self.new_level_container.get_size().y) -
    self.separation

proc expanded_new_level_margin(self: Settings): int =
  self.collapsed_new_level_margin +
    int(self.new_level_container.get_size().y / 2.0) + self.separation + 10

proc resize(self: Settings, start_margin, end_margin: float, node: Node, property: string) =
  let tween = self.create_tween[]
  # For Godot 4, set_trans and set_ease need proper enum types
  # But for now we'll skip setting these and use defaults
  # discard tween.set_trans(transition)
  # discard tween.set_ease(ease_in_out)
  discard tween.tween_property(
    node, newNodePath(property),
    variant(end_margin),
    animation_duration
  )

proc resize(self: Settings, start_margin, end_margin: int, node: Node, property: string) =
  self.main_container.add_theme_constant_override(property, start_margin.int32)
  self.resize(float(start_margin), float(end_margin), node, property)

proc margin_y(self: Settings): int =
  self.main_container.get_theme_constant("margin_bottom")

proc margin_x(self: Settings): int =
  self.main_container.get_theme_constant("margin_left")

proc resize_x(self: Settings, start_margin, end_margin: int) =
  let start_margin = self.margin_x
  self.resize(
    start_margin,
    end_margin,
    node = self.main_container,
    property = "theme_override_constants/margin_left",
  )

proc resize_y(self: Settings, start_margin, end_margin: int) =
  let start_margin = self.margin_y
  self.resize(
    start_margin,
    end_margin,
    node = self.main_container,
    property = "theme_override_constants/margin_bottom",
  )

proc resize_x(self: Settings, end_margin: int) =
  self.resize_x(self.margin_x, end_margin)

proc resize_y(self: Settings, end_margin: int) =
  self.resize_y(self.margin_y, end_margin)

proc open_window(self: Settings) =
  self.update_level_list()
  self.update_values()
  self.state = Opened
  self.window.set_visible(true)
  self.action_steps =
    @[
      proc() =
        self.window.anchor_left = 1.0,
      proc() =
        self.window.set_modulate(gdext.color(1.0, 1.0, 1.0, 1.0))
        self.resize(1.0, 0.0, node = self.window, property = "anchor_right"),
      proc() =
        self.resize_y self.expanded_margin()
      ,
    ]

proc close_window(self: Settings) =
  self.action_steps =
    if self.state != NewLevel:
      @[
        proc() =
          self.resize_y self.collapsed_margin()
        ,
        proc() =
          self.resize(0.0, 1.0, node = self.window, property = "anchor_left"),
        proc() =
          self.window.set_modulate(gdext.color(1.0, 1.0, 1.0, 0.0))
          self.window.set_visible(false),
      ]
    else:
      @[
        proc() =
          self.resize_y(
            self.expanded_new_level_margin, self.collapsed_new_level_margin
          ),
        proc() =
          self.new_level_container.set_visible(false)
          self.main_container.add_theme_constant_override(
            "margin_bottom", self.collapsed_margin.int32
          ),
        proc() =
          self.resize(0.0, 1.0, node = self.window, property = "anchor_left"),
        proc() =
          self.window.set_modulate(gdext.color(1.0, 1.0, 1.0, 0.0))
          self.window.set_visible(false),
      ]
  self.state = Closed

proc show_new_level(self: Settings) =
  self.level_name.set_text("")
  self.new_level_container.set_visible(false)
  self.state = NewLevel
  self.action_steps =
    @[
      proc() =
        self.resize_y(self.expanded_margin, self.collapsed_margin),
      proc() =
        self.new_level_container.set_visible(true)
        self.level_name.grab_focus()
        self.main_container.add_theme_constant_override(
          "margin_bottom", self.collapsed_new_level_margin.int32
        ),
      proc() =
        self.resize_y(
          self.collapsed_new_level_margin, self.expanded_new_level_margin
        ),
    ]

proc approximate_full_width(self: Settings): float =
  let width = self.settings_container.get_size().x
  let columns = self.settings_container.get_columns()
  let column_width = width / float(columns)
  result =
    (column_width * 4) + 80 - (9 * float self.settings_container.get_columns())

method ready*(self: Settings) {.gdsync.} =
  self.size_timer = MonoTime.high
  self.state = None

  with self:
    environments = find("Environments", OptionButton)
    colors = find("PlayerColors", OptionButton)
    levels = find("Levels", OptionButton)
    megapixels = find("Megapixels", LineEdit)
    font_size = find("FontSize", LineEdit)
    toolbar_size = find("ToolbarSize", LineEdit)
    server_address = find("ServerAddress", LineEdit)
    level_name = find("LevelName", LineEdit)
    megapixels_up = find("MegapixelsUp", Button)
    megapixels_down = find("MegapixelsDown", Button)
    font_size_up = find("FontSizeUp", Button)
    font_size_down = find("FontSizeDown", Button)
    toolbar_size_up = find("ToolbarSizeUp", Button)
    toolbar_size_down = find("ToolbarSizeDown", Button)
    full_screen = find("FullScreen", Button)
    run_server = find("RunServer", Button)
    connect = find("Connect", Button)
    save = find("Save", Button)
    cancel = find("Cancel", Button)
    remote_container = find("RemoteContainer", Container)
    main_container = find("MainContainer", Container)
    new_level_container = find("NewLevelContainer", Container)
    row_container = find("RowContainer", Container)
    settings_container = find("SettingsContainer", GridContainer)
    window = find("Window", Container)
    close = find("Close", Button)
    separation = 4 # Default separation, TODO: get from theme
    left_separator = find("LeftSeparator", VSeparator)
    right_separator = find("RightSeparator", VSeparator)

  self.environments.add_item("default")
  for env in environments.keys.to_seq.sorted:
    if env notin ["default", "none"]:
      self.environments.add_item(env)
  self.environments.add_item("none")

  var add_hex = true
  for color in Colors:
    if color != Eraser:
      self.colors.add_item($color)
      if state.config.player_color == action_colors[color]:
        add_hex = false
        self.colors.select(self.colors.get_item_count - 1)
  if add_hex:
    self.colors.add_item(state.config.player_color.to_html_hex)
    self.colors.select(self.colors.get_item_count - 1)

  for button in [
    self.megapixels_up, self.megapixels_down, self.font_size_up,
    self.font_size_down, self.toolbar_size_up, self.toolbar_size_down,
  ]:
    self.bind_signal(button, "pressed", button.get_name())
    self.bind_signal(button, "button_up", button.get_name())
    self.bind_signal(button, "button_down", button.get_name())

  for option_button in [self.environments, self.colors, self.levels]:
    self.bind_signal(option_button, "item_selected", option_button.get_name())

  self.bind_signal(self.connect, "pressed", "Connect")
  self.bind_signal(self.close, ("pressed", "closed"))
  self.bind_signal(self.cancel, ("pressed", "cancelled"))
  self.bind_signal(self.save, "pressed", self.save.get_name())

  for button in [self.full_screen, self.run_server]:
    self.bind_signal(button, ("pressed", "toggled"), button, button.get_text())

  for line_edit in [self.level_name, self.server_address]:
    self.bind_signal(line_edit, "text_submitted", line_edit.get_name())

  state.nodes.game.bind_signal(self, "gui_input", self.get_name())

  self.update_level_list()
  self.update_values()

  state.config_value.changes:
    self.update_values()

  state.local_flags.changes:
    if SettingsVisible.added:
      self.open_window()
    elif SettingsVisible.removed:
      self.close_window()
    elif CommandMode.added:
      self.ghost()
    elif CommandMode.removed:
      self.unghost()

  if SettingsVisible notin state.local_flags:
    self.window.set_modulate(gdext.color(1.0, 1.0, 1.0, 0.0))
    if SceneReady in state.local_flags:
      self.close_window
    else:
      state.local_flags.changes:
        if SceneReady.added:
          self.close_window

proc on_pressed(self: Settings, name: string) =
  if find(name, Button).is_disabled():
    return

  const megapixel_steps = [
    (low: 0.01, high: 0.05, step: 0.01),
    (0.05, 0.4, 0.05),
    (0.4, 1.0, 0.1),
    (1.0, 4.0, 0.5),
    (4.0, 10.0, 1.0),
  ]
  if name == "MegapixelsUp":
    let megapixels = state.config.megapixels
    for step in megapixel_steps:
      if megapixels < step.high:
        state.config_value.value:
          megapixels = round(megapixels + step.step, 2)
        break
  elif name == "MegapixelsDown":
    let megapixels = state.config.megapixels
    for step in megapixel_steps.reversed:
      if megapixels > step.low:
        state.config_value.value:
          megapixels = round(megapixels - step.step, 2)
        break

  if name == "FontSizeUp" and state.config.font_size < 42:
    state.config_value.value:
      font_size = state.config.font_size + 1
  elif name == "FontSizeDown" and state.config.font_size > 4:
    state.config_value.value:
      font_size = state.config.font_size - 1
  elif name == "ToolbarSizeUp" and state.config.toolbar_size < 120:
    state.config_value.value:
      toolbar_size = state.config.toolbar_size + 5
  elif name == "ToolbarSizeDown" and state.config.toolbar_size > 20:
    state.config_value.value:
      toolbar_size = state.config.toolbar_size - 5
  elif name == "Connect" and not ?state.config.connect_address and
      ?($self.server_address.get_text()):
    state.config_value.value:
      connect_address = $self.server_address.get_text()
    state.pop_flags SettingsFocused, SettingsVisible
    state.push_flag NeedsRestart
  elif name == "Connect" and $self.connect.get_text() == "Disconnect":
    state.config_value.value:
      connect_address = ""
    state.pop_flags SettingsFocused, SettingsVisible
    state.push_flag NeedsRestart
  elif name == "Save":
    if is_valid_file_name($self.level_name.get_text()):
      change_loaded_level($self.level_name.get_text(), state.config.world)
      state.pop_flag SettingsVisible

  self.update_values()

proc on_closed(self: Settings) =
  state.pop_flag SettingsVisible

proc on_cancelled(self: Settings) =
  self.update_values()
  self.state = Opened
  self.action_steps =
    @[
      proc() =
        self.resize_y(
          self.expanded_new_level_margin, self.collapsed_new_level_margin
        ),
      proc() =
        self.new_level_container.set_visible(false)
        self.main_container.add_theme_constant_override(
          "margin_bottom", self.collapsed_margin.int32.int32
        ),
      proc() =
        self.resize_y(self.collapsed_margin, self.expanded_margin),
    ]

proc on_button_up(self: Settings, name: string) =
  self.repeat_timers[name] = MonoTime.high

proc on_button_down(self: Settings, name: string) =
  self.repeat_timers[name] = get_mono_time() + 0.4.seconds

proc on_toggled(self: Settings, button: Button, default: string) =
  let current = $button.get_text() == check
  let enable = not current
  if not enable:
    button.set_text(blank)
  else:
    button.set_text(check)

  if $button.get_name() == "FullScreen":
    state.config_value.value:
      full_screen = enable
  if $button.get_name() == "RunServer":
    state.config_value.value:
      run_server = enable
    if enable:
      self.action_steps.add proc() =
        self.resize_y(self.remote_opened_margin, self.remote_closed_margin)
    else:
      self.action_steps.add proc() =
        self.resize_y(self.remote_closed_margin, self.remote_opened_margin)

  self.update_values()

proc on_item_selected(self: Settings, index: int, name: string) =
  if name == "Environments":
    state.config_value.value:
      environment = $self.environments.get_item_text(index.int32)
      environment_override = ""
  elif name == "Levels":
    if $self.levels.get_text() == "New...":
      self.show_new_level()
    else:
      change_loaded_level($self.levels.get_text(), state.config.world)
      state.pop_flag SettingsVisible
  elif name == "PlayerColors":
    for color in Colors:
      if $self.colors.get_text() == $color:
        state.config_value.value:
          player_color = action_colors[color]
        return
    state.config_value.value:
      player_color = ($self.colors.get_text()).parse_html_hex

proc on_text_submitted(self: Settings, text, name: string) =
  if name == "LevelName":
    self.on_pressed("Save")
  elif name == "ServerAddress":
    self.on_pressed("Connect")

method process*(self: Settings, delta: float) {.gdsync.} =
  let now = get_mono_time()
  for name, time in self.repeat_timers.mpairs:
    if now > time:
      time = now + 0.14.seconds
      self.on_pressed(name)

  if self.action_steps.len > 0:
    let step = self.action_steps[0]
    self.action_steps.delete(0)
    step()
  elif self.action_steps.len == 0 and self.state == Opened and
      self.margin_y != self.expanded_margin:
    self.resize_y(self.expanded_margin)

  if self.state == Opened:
    let viewport = self.get_viewport()
    let width = self.approximate_full_width
    let viewport_rect = viewport.get_visible_rect()
    let viewport_size = viewport_rect.size
    if width > viewport_size.x and
        (self.window.get_size().y * 1.2) < viewport_size.y:
      self.settings_container.set_columns(2)
      self.left_separator.set_stretch_ratio(0.0)
      self.right_separator.set_stretch_ratio(0.0)
    elif viewport_size.x > width + 10:
      self.settings_container.set_columns(4)
      self.left_separator.set_stretch_ratio(0.5)
      self.right_separator.set_stretch_ratio(0.5)

method unhandled_input*(self: Settings, event: InputEvent) {.gdsync.} =
  if SettingsFocused in state.local_flags and
      event.is_action_pressed("ui_cancel"):
    if not (event of InputEventJoypadButton) or
        CommandMode notin state.local_flags:
      if self.state == NewLevel:
        self.on_cancelled()
      else:
        state.pop_flag SettingsVisible
      self.get_viewport().set_input_as_handled()
