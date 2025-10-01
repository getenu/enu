import std/[options, strutils]
import gdext
# Use custom Godot bindings for consistency with Game and BuildNode
import gdext/classes/[gdbutton, gdviewport, gdstyleboxflat, gdinputevent]
import core, gdcore, types, models/states

type ActionButton* {.gdsync.} = ptr object of Button

proc update_size*(self: ActionButton) =
  # Use state.config.toolbar_size like Godot 3, applying screen scale
  var toolbar_size = state.config.toolbar_size * state.config.screen_scale
  let viewport_width = self.get_viewport().get_visible_rect().size.x

  # Original Godot 3 logic: if (toolbar_size + 4) * 8 > viewport_width: resize to fit
  if (toolbar_size + 4.0) * 8.0 > viewport_width:
    toolbar_size = viewport_width / 8.0 - 4.0

  let size_vec = vector2(toolbar_size, toolbar_size)
  self.set_custom_minimum_size(size_vec)

  # Update corner radius for responsive design
  let corner_radius = (8.0 * (toolbar_size / 100.0)).int32

  # Update style boxes with new corner radius
  for style in ["hover", "pressed", "focus", "normal"]:
    let stylebox = self.getThemeStylebox(new_string_name(style))
    if ?stylebox and stylebox[].is_class("StyleBoxFlat"):
      let flat_style = stylebox.as(gdref StyleBoxFlat)
      if ?flat_style:
        flat_style[].setCornerRadiusAll(corner_radius)

proc trigger_action_changed(self: ActionButton) =
  ## Trigger action_changed signal to notify Toolbar of tool selection
  let button_name = $self.get_name()
  print("[UI] ActionButton trigger_action_changed: " & button_name)

  # Emit signal to the parent Toolbar (same as Godot 3 version)
  let parent = self.get_parent()
  if ?parent:
    # Create and emit the action_changed signal with the button name
    parent.trigger("action_changed", variant(button_name))
  else:
    print("[UI] ERROR: parent not available for signal routing")

method onInit*(self: ActionButton) =
  # Constructor-like initialization
  discard

method ready*(self: ActionButton) {.gdsync.} =
  print("[UI] ActionButton ready: " & $self.get_name())

  # Set up initial size
  self.update_size()

  # Connect to config changes like Godot 3
  state.config_value.changes:
    if state.config.toolbar_size != change.item.toolbar_size:
      self.update_size()

  # Connect to viewport size changes like Godot 3
  discard self.get_viewport().connect(
    "size_changed", self.callable("_on_size_changed")
  )

  # Connect button press signal
  discard self.connect("pressed", self.callable("_on_pressed"))

proc on_pressed*(self: ActionButton) {.gdsync, name: "_on_pressed".} =
  print("[UI] ActionButton pressed: " & $self.get_name())
  self.trigger_action_changed()

proc on_size_changed*(self: ActionButton) {.gdsync, name: "_on_size_changed".} =
  print("[UI] ActionButton size changed: " & $self.get_name())
  self.update_size()
