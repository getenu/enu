import godotapi/[button, control, scene_tree, input_event_mouse_button]
import godot
import core, gdutils

gdobj FloatingButton of Button:
  method gui_input(event: InputEvent) =
    self.accept_event()
