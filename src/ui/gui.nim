import gdext
import gdext/classes/[gdcontrol, gdbutton, gdinputevent, gdinputeventaction,
                     gdinputeventscreentouch, gdinputeventscreendrag,
                     gdinputeventkey, gdinputeventjoypadbutton, gdinputeventjoypadmotion,
                     gdinputeventmousemotion, gdinputeventmousebutton,
                     gdinputeventpangesture, gdnode, gdinput, gdviewport, gdtween]
import core, gdutils, types, models/states
import std/times, std/options

const
  fly_toggle = 0.3.seconds
  input_command_timeout = 0.25
  first_delete = 0.5.seconds
  # Responsive design thresholds
  narrow_screen_threshold = 1200.0  # Below this width, panels become narrow
  mobile_screen_threshold = 800.0   # Below this width, panels become full-width overlays

type GUI* {.gdsync.} = ptr object of Control
  left_stick: Control
  up: Button
  down: Button
  # Panel references
  left_panel: Control
  right_panel: Control
  # Panel animation tweens
  left_tween: gdref Tween
  right_tween: gdref Tween
  # Responsive design state
  current_screen_width: float
  is_narrow_screen: bool
  is_mobile_screen: bool
  # Player input state fields
  command_timer: float
  input_relative*: Vector2
  pan_delta: float
  touch_position: Option[Vector2]
  delete_timer: MonoTime
  deleting: bool

# Forward declarations - all procedures must be defined before ready() method
proc configure_mobile_layout(self: GUI) =
  # Position overrides disabled - panels remain at their scene-defined positions
  # # Configure panels for mobile screens (full-width overlays)
  # if ?self.left_panel:
  #   # Set left panel to fill entire width (0-1.0)
  #   self.left_panel.set_anchor(sideLeft, 0.0)
  #   self.left_panel.set_anchor(sideRight, 1.0)
  # if ?self.right_panel:
  #   # Set right panel to fill entire width (0-1.0)
  #   self.right_panel.set_anchor(sideLeft, 0.0)
  #   self.right_panel.set_anchor(sideRight, 1.0)
  print("[UI] Mobile layout (position overrides disabled)")

proc configure_narrow_layout(self: GUI) =
  # Position overrides disabled - panels remain at their scene-defined positions
  # # Configure panels for narrow screens (reduced width)
  # if ?self.left_panel:
  #   # Set left panel to 60% width (0-0.6)
  #   self.left_panel.set_anchor(sideLeft, 0.0)
  #   self.left_panel.set_anchor(sideRight, 0.6)
  # if ?self.right_panel:
  #   # Set right panel to start at 40% and fill to right (0.4-1.0)
  #   self.right_panel.set_anchor(sideLeft, 0.4)
  #   self.right_panel.set_anchor(sideRight, 1.0)
  print("[UI] Narrow layout (position overrides disabled)")

proc configure_standard_layout(self: GUI) =
  # Position overrides disabled - panels remain at their scene-defined positions
  # # Configure panels for standard screens (normal 50/50 split)
  # if ?self.left_panel:
  #   # Set left panel to 50% width (0-0.5)
  #   self.left_panel.set_anchor(sideLeft, 0.0)
  #   self.left_panel.set_anchor(sideRight, 0.5)
  # if ?self.right_panel:
  #   # Set right panel to start at 50% and fill to right (0.5-1.0)
  #   self.right_panel.set_anchor(sideLeft, 0.5)
  #   self.right_panel.set_anchor(sideRight, 1.0)
  print("[UI] Standard layout (position overrides disabled)")

proc apply_responsive_layout(self: GUI) =
  # Apply layout changes based on screen size
  if self.is_mobile_screen:
    # Mobile: Full-width overlays
    self.configure_mobile_layout()
  elif self.is_narrow_screen:
    # Narrow: Reduced panel widths
    self.configure_narrow_layout()
  else:
    # Normal: Standard panel sizes
    self.configure_standard_layout()

proc show_left_panel(self: GUI) =
  if not ?self.left_panel:
    return

  # Animation disabled - show panel directly
  # # Kill existing tween
  # if ?self.left_tween:
  #   self.left_tween[].kill()
  #
  # self.left_tween = self.create_tween()
  # # Start from off-screen left and animate to normal position
  # let panel_width = self.left_panel.get_size().x
  # self.left_panel.set_position(vector2(-panel_width, self.left_panel.get_position().y))
  #
  # # Animate sliding in from left
  # discard self.left_tween[].tween_property(
  #   self.left_panel,
  #   "position:x",
  #   variant(0.0),
  #   animation_duration
  # )
  # discard self.left_tween[].set_trans(transExpo)
  # discard self.left_tween[].set_ease(easeOut)

  self.left_panel.set_visible(true)

proc hide_left_panel(self: GUI) =
  if not ?self.left_panel:
    return

  # Animation disabled - hide panel directly
  self.left_panel.set_visible(false)

proc show_right_panel(self: GUI) =
  if not ?self.right_panel:
    return

  # Animation disabled - show panel directly
  self.right_panel.set_visible(true)

proc hide_right_panel(self: GUI) =
  if not ?self.right_panel:
    return

  # Animation disabled - hide panel directly
  self.right_panel.set_visible(false)

proc watch_panel_states(self: GUI) =
  # Watch for panel visibility state changes and trigger animations
  state.local_flags.changes:
    # Left panel animations (Editor/Console)
    if EditorVisible.added or ConsoleVisible.added:
      self.show_left_panel()
    elif EditorVisible.removed and ConsoleVisible.removed:
      self.hide_left_panel()

    # Right panel animations (Docs)
    if DocsVisible.added:
      self.show_right_panel()
    elif DocsVisible.removed:
      self.hide_right_panel()

method ready*(self: GUI) {.gdsync.} =
  print("[UI] GUI ready - initializing main UI coordination system")

  # Initialize state
  self.delete_timer = MonoTime.high
  self.input_relative = vector2()

  # Find child controls for touch controls
  self.left_stick = self.find("LeftStick", Control)
  self.up = self.find("Up", Button)
  self.down = self.find("Down", Button)

  # Find panel controls for animations
  let panels_container = self.find("Panels", Control)
  if ?panels_container:
    self.left_panel = panels_container.find("LeftPanel", Control)
    self.right_panel = panels_container.find("RightPanel", Control)

  # Panels start hidden until triggered by state flags
  if ?self.left_panel:
    self.left_panel.set_visible(false)
    print("[UI] Left panel initialized (hidden)")
  if ?self.right_panel:
    self.right_panel.set_visible(false)
    print("[UI] Right panel initialized (hidden)")

  # Initialize responsive design state (will be updated in process())
  self.current_screen_width = 0.0

  # Bind settings button
  let settings_button = self.find("OpenSettings", Button)
  if not settings_button.is_nil:
    discard settings_button.connect("pressed", self.callable("_on_settings_opened"))
    print("[UI] Settings button connected to signal handler")

  # Set up panel state watching
  self.watch_panel_states()

  # Start with panels hidden - they'll be shown based on user interaction
  print("[UI] Panel visibility controlled by state flags")

  print("[UI] GUI configured with responsive panels and input handling")

proc on_settings_opened(self: GUI) {.gdsync, name: "_on_settings_opened".} =
  # Open settings panel
  print("[UI] Settings button pressed - opening settings panel")
  state.push_flags SettingsVisible

proc update_responsive_design(self: GUI) =
  # Update responsive design based on current screen size
  let viewport = self.get_viewport()
  if not ?viewport:
    return

  let new_width = viewport.get_visible_rect().size.x
  let width_changed = abs(new_width - self.current_screen_width) > 10.0

  if width_changed:
    self.current_screen_width = new_width
    let was_narrow = self.is_narrow_screen
    let was_mobile = self.is_mobile_screen

    # Update screen size flags
    self.is_mobile_screen = new_width < mobile_screen_threshold
    self.is_narrow_screen = new_width < narrow_screen_threshold

    # Apply responsive changes if screen size category changed
    if was_narrow != self.is_narrow_screen or was_mobile != self.is_mobile_screen:
      self.apply_responsive_layout()

proc handle_basic_input(self: GUI, event: InputEvent) =
  # Simplified input handling for working compilation

  # Handle primary action (fire)
  if event.is_action_pressed("fire"):
    state.push_flags PrimaryDown
  elif event.is_action_released("fire"):
    state.pop_flags PrimaryDown

  # Handle secondary action (remove)
  if event.is_action_pressed("remove"):
    state.push_flags SecondaryDown
  elif event.is_action_released("remove"):
    state.pop_flags SecondaryDown

  # Handle jump
  if event.is_action_pressed("jump"):
    self.get_viewport().set_input_as_handled()
    # Simple jump handling - can be expanded later

  # Handle pan gestures for tool cycling
  if event.is_class("InputEventPanGesture"):
    let pan_event = event.as(InputEventPanGesture)
    self.pan_delta += pan_event.get_delta().y

    if self.pan_delta > 2:
      self.pan_delta = 0
      # state.cycle_tool(1) - TODO: Add when tool cycling is available
    elif self.pan_delta < -2:
      self.pan_delta = 0
      # state.cycle_tool(-1) - TODO: Add when tool cycling is available

method unhandled_input*(self: GUI, event: gdref InputEvent) {.gdsync.} =
  # Handle global input events and UI navigation
  let event = event[]
  if CommandMode notin state.local_flags and event.is_action_pressed("ui_cancel") and ViewportFocused in state.local_flags:
    let flags = state.try_pop(ViewportFocused)

    if SettingsFocused in flags:
      state.pop_flags SettingsFocused, SettingsVisible
    elif EditorFocused in flags:
      state.open_unit = nil
    elif DocsFocused in flags:
      state.open_sign = nil

  # Forward input to basic handling
  if event.is_class("InputEventKey") or event.is_class("InputEventAction") or
     event.is_class("InputEventJoypadButton") or event.is_class("InputEventPanGesture"):
    self.handle_basic_input(event)

method gui_input*(self: GUI, event: gdref InputEvent) {.gdsync.} =
  # Handle direct GUI input events, especially for touch controls
  if event[].is_class("InputEventScreenTouch"):
    let touch_event = event[].as(InputEventScreenTouch)
    let index = byte(touch_event.get_index())

    if TouchControls in state.local_flags and index notin state.ignored_touches:
      if touch_event.get_index() == 0:
        if touch_event.is_pressed():
          self.touch_position = some(touch_event.get_position())
          self.delete_timer = get_mono_time() + first_delete
        else:
          # Simple tap handling
          if self.touch_position.is_some and self.touch_position.get() == touch_event.get_position():
            state.push_flags PrimaryDown
            state.pop_flags PrimaryDown
            self.deleting = false
            self.delete_timer = MonoTime.high
            self.touch_position = none(Vector2)
    elif index in state.ignored_touches and not touch_event.is_pressed():
      state.ignored_touches.excl(index)
      self.get_viewport().set_input_as_handled()

  elif event[].is_class("InputEventScreenDrag"):
    let drag_event = event[].as(InputEventScreenDrag)
    let index = byte(drag_event.get_index())

    if TouchControls in state.local_flags and index notin state.ignored_touches:
      if drag_event.get_index() == 0:
        self.touch_position = none(Vector2)
        # Handle camera movement through drag
        self.input_relative += drag_event.get_relative()

        if not self.deleting:
          self.delete_timer = MonoTime.high

  elif event[].is_class("InputEventMouseMotion"):
    # Handle mouse motion for camera control
    if MouseCaptured in state.local_flags and TouchControls notin state.local_flags:
      let mouse_event = event[].as(InputEventMouseMotion)
      self.input_relative += mouse_event.get_relative()

  elif event[].is_class("InputEventMouseButton"):
    self.handle_basic_input(event[])

method process*(self: GUI, delta: float64) {.gdsync.} =
  # Update GUI state each frame
  if self.command_timer > 0:
    self.command_timer -= delta
    if self.command_timer <= 0:
      state.pop_flags CommandMode

  # Handle touch delete timing
  if self.delete_timer != MonoTime.high and get_mono_time() > self.delete_timer:
    if not self.deleting:
      self.deleting = true
      state.push_flags SecondaryDown

  # TODO: Check for screen size changes for responsive design
  # self.update_responsive_design()  # Commented out to fix build

  # Forward accumulated input to player if available
  if self.input_relative.length_squared() > 0:
    # TODO: Forward to player node when available
    # state.nodes.player.handle_mouse_motion(self.input_relative)
    self.input_relative = vector2()
