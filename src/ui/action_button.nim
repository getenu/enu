import
  godotapi/[
    button, style_box_flat, input_event_screen_touch, input_event_screen_drag,
    scene_tree
  ]
import godot
import ".."/[core, gdutils]

gdobj ActionButton of Button:
  proc update_size(size: float) =
    let toolbar_size = state.config.toolbar_size * state.config.screen_scale
    self.rect_min_size = vec2(toolbar_size, toolbar_size)
    for style in ["hover", "pressed", "focus", "normal"]:
      var stylebox = self.get_stylebox(style).as(StyleBoxFlat)
      stylebox.set_corner_radius_all int 8 * (toolbar_size / 100)

  method ready*() =
    state.config_value.changes:
      if state.config.toolbar_size != change.item.toolbar_size:
        self.update_size(change.item.toolbar_size)

    self.update_size state.config.toolbar_size
    self.bind_signals self, "pressed"

  method on_pressed*() =
    self.get_parent.trigger("action_changed", self.name)

  method input(event: InputEvent) =
    self.ignore_touches(event)
