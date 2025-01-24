import pkg/godot
import
  godotapi/[
    control, input_event_screen_touch, input_event_screen_drag, scene_tree,
    input_event_action, input, button, gd_os,
  ]
import core, nodes/player_node, gdutils

gdobj GUI of Control:
  var
    left_stick: Control
    up: Button
    down: Button

  method ready() =
    self.left_stick = find("LeftStick", Control)
    self.up = find("Up", Button)
    self.down = find("Down", Button)

    self.bind_signals self,
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

  method unhandled_input*(event: InputEvent) =
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
      (state.nodes.player as PlayerNode).viewport_input(event)
      # self.get_tree().set_input_as_handled()
      # self.accept_event()

  # method gui_input(event: InputEvent) =
  #   (state.nodes.player as PlayerNode).viewport_input(event)
  #   self.accept_event()

  method gui_input*(event: InputEvent) =
    template touch_controls() =
      if TouchControls in state.local_flags:
        let index = byte(event.index)
        if index notin state.ignored_touches:
          (state.nodes.player as PlayerNode).viewport_input(event)
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
      (state.nodes.player as PlayerNode).viewport_input(event)
      # self.get_tree().set_input_as_handled()
      # self.accept_event()

  method process(delta: float) =
    self.margin_bottom = float(get_virtual_keyboard_height() * -1)
