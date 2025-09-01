import gdext
import gdext/classes/[gdcontrol, gdbutton, gdinputevent, gdinputeventaction, 
                     gdinputeventscreentouch, gdinputeventscreendrag, 
                     gdinputeventkey, gdinputeventjoypadbutton, gdinputeventjoypadmotion,
                     gdinputeventmousemotion, gdinputeventmousebutton, 
                     gdinputeventpangesture, gdnode, gdinput, gdviewport]
import core, gdutils, types, models/states
import std/times, std/options

const
  fly_toggle = 0.3.seconds
  input_command_timeout = 0.25
  first_delete = 0.5.seconds

type GUI* {.gdsync.} = ptr object of Control
  left_stick: Control
  up: Button
  down: Button
  # Player input state fields
  command_timer: float
  input_relative*: Vector2
  pan_delta: float
  touch_position: Option[Vector2]
  delete_timer: MonoTime
  deleting: bool

method ready*(self: GUI) {.gdsync.} =
  print("[UI] GUI ready - initializing main UI coordination system")
  
  # Initialize state
  self.delete_timer = MonoTime.high
  self.input_relative = vector2()
  
  # Find child controls for touch controls
  self.left_stick = self.find("LeftStick", Control)
  self.up = self.find("Up", Button)  
  self.down = self.find("Down", Button)
  
  # Bind settings button
  let settings_button = self.find("OpenSettings", Button)
  if not settings_button.is_nil:
    self.bind_signal(settings_button, ("pressed", "settings_opened"))
  
  # TODO: Add state watching for touch controls visibility
  
  print("[UI] GUI configured with basic input handling and UI coordination")

proc on_settings_opened(self: GUI) =
  # Open settings panel
  state.push_flags SettingsVisible

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

method unhandled_input*(self: GUI, event: InputEvent) {.gdsync.} =
  # Handle global input events and UI navigation
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

method gui_input*(self: GUI, event: InputEvent) {.gdsync.} =
  # Handle direct GUI input events, especially for touch controls
  if event.is_class("InputEventScreenTouch"):
    let touch_event = event.as(InputEventScreenTouch)
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
      
  elif event.is_class("InputEventScreenDrag"):
    let drag_event = event.as(InputEventScreenDrag) 
    let index = byte(drag_event.get_index())
    
    if TouchControls in state.local_flags and index notin state.ignored_touches:
      if drag_event.get_index() == 0:
        self.touch_position = none(Vector2)
        # Handle camera movement through drag
        self.input_relative += drag_event.get_relative()
        
        if not self.deleting:
          self.delete_timer = MonoTime.high
          
  elif event.is_class("InputEventMouseMotion"):
    # Handle mouse motion for camera control
    if MouseCaptured in state.local_flags and TouchControls notin state.local_flags:
      let mouse_event = event.as(InputEventMouseMotion)
      self.input_relative += mouse_event.get_relative()
      
  elif event.is_class("InputEventMouseButton"):
    self.handle_basic_input(event)

method process*(self: GUI, delta: float) {.gdsync.} =
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
  
  # Forward accumulated input to player if available  
  if self.input_relative.length_squared() > 0:
    # TODO: Forward to player node when available
    # state.nodes.player.handle_mouse_motion(self.input_relative)
    self.input_relative = vector2()