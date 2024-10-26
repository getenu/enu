import pkg/godot
import
  godotapi/[
    control, input_event_screen_touch, input_event_screen_drag, scene_tree,
    input_event_action, input
  ]
import core, nodes/player_node, gdutils

gdobj GUI of Control:
  var
    left_stick: Control
    up: Control
    down: Control

  method ready() =
    self.left_stick = find("LeftStick", Control)
    self.up = find("Up", Control)
    self.down = find("Down", Control)

    self.bind_signals self,
      "mouse_entered", "mouse_exited", "focus_entered", "focus_exited"

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

  method on_mouse_entered() =
    state.push_flag ViewportFocused

  method on_mouse_exited() =
    state.pop_flag ViewportFocused

  method on_focus_entered() =
    state.push_flag ViewportFocused

  method on_focus_exited() =
    state.pop_flag ViewportFocused

  method gui_input(event: InputEvent) =
    (state.nodes.player as PlayerNode).viewport_input(event)
    self.accept_event()

  method input(event: InputEvent) =
    if event of InputEventScreenTouch:
      let event = event as InputEventScreenTouch
      let index = byte(event.index)
      if index in state.ignored_touches:
        self.get_tree().set_input_as_handled()
        if not event.pressed:
          state.ignored_touches.excl index
    elif event of InputEventScreenDrag:
      let event = event as InputEventScreenDrag
      let index = byte(event.index)
      if index in state.ignored_touches:
        self.get_tree().set_input_as_handled()
        return

    if TouchControls in state.local_flags:
      (state.nodes.player as PlayerNode).viewport_input(event)
    else:
      if event of InputEventKey:
        (state.nodes.player as PlayerNode).viewport_input(event)
