import std/[options, strutils]
import gdext
# Use custom Godot bindings for consistency with Game and BuildNode
import gdext/classes/[gdbutton, gdviewport, gdstyleboxflat, gdinputevent]
import core, gdutils, types, models/states

# Simple state management for the UI components
# This will eventually connect to the full game state system
var global_toolbar_size* = 100.0
var global_screen_scale* = 1.0

type ActionButton* {.gdsync.} = ptr object of Button

proc update_size(self: ActionButton, size: float) =
  var toolbar_size = global_toolbar_size * global_screen_scale
  let viewport_width = self.get_viewport().get_visible_rect().size.x
  
  # Original logic: if (toolbar_size + 4) * 8 > viewport_width: resize to fit  
  if (toolbar_size + 4.0) * 8.0 > viewport_width:
    toolbar_size = viewport_width / 8.0 - 4.0
    
  let size_vec = vector2(toolbar_size, toolbar_size)
  self.set_custom_minimum_size(size_vec)
  
  # Update corner radius for responsive design
  let corner_radius = (8.0 * (toolbar_size / 100.0)).int32
  
  # Update style boxes with new corner radius (simplified for now)
  # TODO: Implement style box updates when we understand gdext GdRef patterns better
  # for style in ["hover", "pressed", "focus", "normal"]:
  #   let stylebox = self.getThemeStylebox(StringName(style))
  #   let flat_style = stylebox as StyleBoxFlat  
  #   flat_style.setCornerRadiusAll(corner_radius)

proc trigger_action_changed(self: ActionButton) =
  ## Trigger action_changed signal to notify Toolbar of tool selection
  let button_name = $self.get_name()
  print("[UI] ActionButton trigger_action_changed: " & button_name)
  
  # Emit signal to the game node which will route it to Toolbar
  let game_node = state.nodes.game
  if ?game_node:
    # Create and emit the action_changed signal with the button name
    game_node.trigger("action_changed", variant(button_name))
  else:
    print("[UI] ERROR: game node not available for signal routing")

method onInit*(self: ActionButton) =
  # Constructor-like initialization
  discard

method ready*(self: ActionButton) {.gdsync.} =
  print("[UI] ActionButton ready: " & $self.get_name())
  
  # Set up initial size
  self.update_size(global_toolbar_size)
  
  # Connect signals using the working Godot 4 signal system
  self.bind_signals(self, "pressed")
  self.bind_signals(self.get_viewport(), "size_changed")
  
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