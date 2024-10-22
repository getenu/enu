import pkg/godot
import
  godotapi/
    [control, input_event_screen_touch, input_event_screen_drag, scene_tree]
import core, nodes/player_node, gdutils

gdobj GUI of Control:
  var left_stick: Control
  method ready() =
    self.bind_signals self,
      "mouse_entered", "mouse_exited", "focus_entered", "focus_exited"
    self.left_stick = find("LeftStick", Control)
    state.local_flags.changes:
      self.left_stick.visible = TouchControls in state.local_flags

  method on_mouse_entered() =
    state.push_flag ViewportFocused

  method on_mouse_exited() =
    state.pop_flag ViewportFocused

  method on_focus_entered() =
    state.push_flag ViewportFocused

  method on_focus_exited() =
    state.pop_flag ViewportFocused

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
