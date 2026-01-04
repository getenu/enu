import pkg/godot
import
  godotapi/[
    control, input_event_screen_touch, input_event_screen_drag, scene_tree,
    input_event_action, input, button, gd_os, input_event_key,
    input_event_joypad_button, input_event_mouse_motion,
    input_event_mouse_button, input_event_pan_gesture, global_constants,
  ]
import core, nodes/player_node, gdutils
import std/times

const
  fly_toggle = 0.3.seconds
  alt_speed_toggle = 0.3.seconds
  nil_time = MonoTime.none
  input_command_timeout = 0.25
  first_delete = 0.5.seconds
  jump_impulse = 10.0

gdobj GUI of Control:
  var
    left_stick: Control
    up: Button
    down: Button
    # Fields moved from PlayerNode
    alt_speed, skip_release, skip_next_mouse_move, jump_down: bool
    jump_time, run_time, crouch_time: Option[MonoTime]
    input_relative* = vec2()
    pan_delta = 0.0
    command_timer = 0.0
    touch_position: Option[Vector2]
    delete_timer = MonoTime.high
    deleting = false

  # Helper to check for active joypad input (moved from PlayerNode)
  proc has_active_input(device: int): bool =
    for axis in 0 .. JOY_AXIS_MAX:
      if axis != JOY_ANALOG_L2 and axis != JOY_ANALOG_R2 and
          get_joy_axis(device, axis).abs >= 0.2:
        return true
    for button in 0 .. JOY_BUTTON_MAX:
      if is_joy_button_pressed(device, button):
        return true

  method ready() =
    self.left_stick = find("LeftStick", Control)
    self.up = find("Up", Button)
    self.down = find("Down", Button)

    for control in [self, self.up, self.down]:
      self.bind_signals control,
        "mouse_entered", "mouse_exited", "focus_entered", "focus_exited"

    self.bind_signal(
      find("OpenSettings", Button), ("pressed", "settings_opened")
    )

    for button in [self.up, self.down]:
      self.bind_signal(button, "button_up", button.name)
      self.bind_signal(button, "button_down", button.name)

    state.local_flags.changes:
      self.left_stick.visible = TouchControls in state.local_flags
      self.up.visible = TouchControls in state.local_flags
      self.down.visible =
        TouchControls in state.local_flags and Flying in state.local_flags

  method on_button_up(name: string) =
    var ev = gdnew[InputEventAction]()
    ev.action = if name == "Up": "jump" else: "crouch"
    ev.pressed = false
    parse_input_event(ev)

  method on_button_down(name: string) =
    var ev = gdnew[InputEventAction]()
    ev.action = if name == "Up": "jump" else: "crouch"
    ev.pressed = true
    parse_input_event(ev)

  method on_settings_opened() =
    state.push_flag SettingsVisible

  method on_mouse_entered() =
    state.push_flag ViewportFocused

  method on_mouse_exited() =
    state.pop_flag ViewportFocused

  method on_focus_entered() =
    state.push_flag ViewportFocused

  method on_focus_exited() =
    state.pop_flag ViewportFocused

  method handle_player_input*(event: InputEvent) =
    if not ?self:
      return
    if TestMode in state.local_flags:
      return
    let player = state.nodes.player as PlayerNode
    if not ?player:
      return
    let time = get_mono_time()

    if event of InputEventMouseMotion and MouseCaptured in state.local_flags and
        TouchControls notin state.local_flags:
      if not self.skip_next_mouse_move:
        player.input_relative += event.as(InputEventMouseMotion).relative()
      else:
        self.skip_next_mouse_move = false

    if event of InputEventScreenTouch and TouchControls in state.local_flags:
      let event = event as InputEventScreenTouch
      if event.index == 0:
        if event.pressed:
          self.touch_position = some event.position
          self.delete_timer = get_mono_time() + first_delete
        else:
          if ?self.touch_position and self.touch_position.get == event.position:
            player.update_raycast()
            state.push_flag PrimaryDown
            state.pop_flag PrimaryDown
            self.deleting = false
            self.delete_timer = MonoTime.high
            self.touch_position = none(Vector2)

    if event of InputEventScreenDrag and TouchControls in state.local_flags:
      let event = event as InputEventScreenDrag
      if event.index == 0:
        self.touch_position = none(Vector2)
      player.input_relative += event.relative()
      if not self.deleting:
        self.delete_timer = MonoTime.high

    if EditorVisible in state.local_flags and not self.skip_release and
        (event of InputEventJoypadButton or event of InputEventJoypadMotion):
      let active_input = self.has_active_input(event.device.int)
      if CommandMode in state.local_flags and not active_input:
        self.command_timer = input_command_timeout
      elif CommandMode in state.local_flags and active_input:
        self.command_timer = 0.0
      elif active_input:
        self.command_timer = 0.0
        state.push_flag CommandMode

    if event.is_action_pressed("jump"):
      self.get_tree().set_input_as_handled()
      self.jump_down = true
      let toggle = ?self.jump_time and time < self.jump_time.get + fly_toggle

      if toggle and Playing notin state.local_flags:
        self.jump_time = nil_time
        state.toggle_flag(Flying)
      elif player.is_on_floor():
        player.velocity += vec3(0, jump_impulse, 0)
        self.jump_time = some time
      else:
        self.jump_time = some time
    elif event.is_action_released("jump"):
      self.get_tree().set_input_as_handled()
      self.jump_down = false

    if event.is_action_pressed("crouch") and player.flying:
      self.get_tree().set_input_as_handled()

      if ?self.crouch_time and time < self.crouch_time.get + fly_toggle:
        self.crouch_time = nil_time
        state.set_flag(Flying, false)
      else:
        self.crouch_time = some time

    if event.is_action_pressed("run"):
      self.get_tree().set_input_as_handled()
      let toggle =
        ?self.run_time and time < self.run_time.get + alt_speed_toggle

      if toggle:
        self.run_time = nil_time
        if player.flying:
          state.toggle_flag(AltFlySpeed)
        else:
          state.toggle_flag(AltWalkSpeed)
      else:
        self.run_time = some time
      self.alt_speed = true
    elif event.is_action_released("run"):
      self.get_tree().set_input_as_handled()
      self.alt_speed = false

    if event of InputEventPanGesture and state.tool notin {CodeMode, PlaceBot}:
      let pan = event as InputEventPanGesture
      self.pan_delta += pan.delta.y
      if self.pan_delta > 2:
        self.pan_delta = 0
        state.update_action_index(1)
      elif self.pan_delta < -2:
        self.pan_delta = 0
        state.update_action_index(-1)

    if event.is_action_pressed("fire"):
      if EditorVisible in state.local_flags:
        self.skip_release = true
      state.push_flag PrimaryDown
    elif event.is_action_released("fire"):
      self.skip_release = false
      state.pop_flag PrimaryDown

    if event.is_action_pressed("remove"):
      state.push_flag SecondaryDown
    elif event.is_action_released("remove"):
      state.pop_flag SecondaryDown

  method unhandled_input*(event: InputEvent) =
    if TestMode in state.local_flags:
      return
    if CommandMode notin state.local_flags and
        event.is_action_pressed("ui_cancel") and
        ViewportFocused in state.local_flags:
      let flags = state.try_pop(ViewportFocused)
      if SettingsFocused in flags:
        state.pop_flags SettingsFocused, SettingsVisible
      elif EditorFocused in flags:
        state.open_unit = nil
      elif DocsFocused in flags:
        state.open_sign = nil

    if event of InputEventKey or event of InputEventAction:
      self.handle_player_input(event)
      # self.get_tree().set_input_as_handled()
      # self.accept_event()

    if event of InputEventJoypadButton:
      self.handle_player_input(event)

  # method gui_input(event: InputEvent) =
  #   (state.nodes.player as PlayerNode).viewport_input(event)
  #   self.accept_event()

  method gui_input*(event: InputEvent) =
    if TestMode in state.local_flags:
      return
    template touch_controls() =
      if TouchControls in state.local_flags:
        let index = byte(event.index)
        if index notin state.ignored_touches:
          self.handle_player_input(event)
        self.accept_event()

    if event of InputEventScreenTouch:
      let event = event as InputEventScreenTouch
      let index = byte(event.index)
      if index in state.ignored_touches:
        self.get_tree().set_input_as_handled()
        if not event.pressed:
          state.ignored_touches.excl index
      touch_controls
    elif event of InputEventScreenDrag:
      let event = event as InputEventScreenDrag
      let index = byte(event.index)
      if index in state.ignored_touches:
        self.get_tree().set_input_as_handled()
        return
      touch_controls
    elif event of InputEventMouseMotion or event of InputEventMouseButton:
      self.handle_player_input(event)
      # self.get_tree().set_input_as_handled()
      # self.accept_event()

  method process(delta: float) =
    self.margin_bottom = float(get_virtual_keyboard_height() * -1)
