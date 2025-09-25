import std/[options, strutils]
import gdext
# Use custom Godot bindings for consistency with Game and BuildNode
import gdext/classes/[gdbutton, gdviewport, gdstyleboxflat, gdinputevent]
import core, gdcore, types, models/states

# Simple state management for the UI components
# This will eventually connect to the full game state system
var global_toolbar_size* = 100.0

type ActionButton* {.gdsync.} = ptr object of Button

proc update_size*(self: ActionButton, size: float) =
  var toolbar_size = size * state.config.screen_scale
  let viewport_width = self.get_viewport().get_visible_rect().size.x

  # Original logic: if (toolbar_size + 4) * 8 > viewport_width: resize to fit
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
  self.update_size(global_toolbar_size)

  # Connect signals using the working Godot 4 signal system
  if not self.has_signal("pressed"):
    self.add_user_signal("pressed")
  let pressed_callable = callable(self, new_string_name("_on_pressed"))
  discard self.connect(new_string_name("pressed"), pressed_callable)

  if not self.get_viewport().has_signal("size_changed"):
    self.get_viewport().add_user_signal("size_changed")
  let size_changed_callable =
    callable(self, new_string_name("_on_size_changed"))
  discard self.get_viewport().connect(
      new_string_name("size_changed"), size_changed_callable
    )

  # TODO: Connect to config changes when state system is available
  # state.config_value.changes:
  #   if state.config.toolbar_size != change.item.toolbar_size:
  #     self.update_size(change.item.toolbar_size)

method pressed*(self: ActionButton) {.gdsync.} =
  print("[UI] ActionButton pressed: " & $self.get_name())
  self.trigger_action_changed()

proc on_size_changed*(self: ActionButton) {.gdsync.} =
  print("[UI] ActionButton size changed: " & $self.get_name())
  self.update_size(global_toolbar_size)
