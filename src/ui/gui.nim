import pkg/godot
import
  godotapi/
    [control, input_event_screen_touch, input_event_screen_drag, scene_tree]
import core, nodes/player_node, gdutils

gdobj GUI of Control:
  method ready() =
    self.bind_signals self,
      "mouse_entered", "mouse_exited", "focus_entered", "focus_exited"

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
    if host_os == "ios":
      (state.nodes.player as PlayerNode).viewport_input(event)
    else:
      if event of InputEventKey:
        (state.nodes.player as PlayerNode).viewport_input(event)

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
