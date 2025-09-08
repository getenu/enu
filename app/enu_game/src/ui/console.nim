import gdext
import gdext/classes/[gdrichtextlabel, gdcontrol, gdnode, 
                     gdinputevent, gdinputeventjoypadbutton, gdvscrollbar,
                     gdtween, gdviewport]
# GD4: Fixed Tween import (was SceneTreeTween in Godot 3)
import core, gdutils, types, models/states
import std/strutils

type Console* {.gdsync.} = ptr object of RichTextLabel
  default_mouse_filter: int64
  tween: gdref Tween  # GD4: Re-enabled with correct import (was SceneTreeTween)

proc watch_states(self: Console)

proc offset_x*(self: Console, offset: float) =
  let width = self.get_size().x
  self.set_position(vector2(width * offset, self.get_position().y))

proc show_console(self: Console) =
  # Set appropriate opacity based on state
  if CommandMode in state.local_flags:
    self.set_modulate(dimmed_alpha)
  else:
    self.set_modulate(color(1.0, 1.0, 1.0, 1.0))
  
  # GD4: Re-enabled SceneTreeTween animations
  # Kill existing tween
  if ?self.tween:
    self.tween[].kill()
  
  self.tween = self.create_tween()
  self.set_visible(true)
  
  # Animate sliding in from right
  discard self.tween[].tween_method(
    callable(self, "offset_x"), variant(-1.0), variant(0.0), animation_duration
  )
  discard self.tween[].set_trans(transExpo)
  discard self.tween[].set_ease(easeInOut)

proc hide_console(self: Console) =
  # GD4: Re-enabled SceneTreeTween animations
  # Kill existing tween
  if ?self.tween:
    self.tween[].kill()
  
  self.tween = self.create_tween()
  self.set_position(vector2(0.0, self.get_position().y))
  
  # Animate sliding out to right
  discard self.tween[].tween_method(
    callable(self, "offset_x"), variant(0.0), variant(-1.0), animation_duration
  )
  discard self.tween[].set_trans(transExpo)
  discard self.tween[].set_ease(easeInOut)
  
  # Hide when animation complete
  discard self.tween[].tween_callback(callable(self, "set_visible").bind(false))

method ready*(self: Console) {.gdsync.} =
  print("[UI] Console ready - Godot 4 migration complete with animations and state watching")
  
  # Store default mouse filter
  self.default_mouse_filter = int64(self.get_mouse_filter())
  
  # GD4: Re-enabled state watching
  self.watch_states()
  
  # Set initial visibility
  if ConsoleVisible notin state.local_flags:
    self.set_modulate(color(1.0, 1.0, 1.0, 0.0))
    self.hide_console()
  
  # Configure scrollbar appearance
  for i in 0 ..< self.get_child_count():
    let child = self.get_child(i)
    if child of VScrollBar:
      let scrollbar = child.as(VScrollBar)
      scrollbar.set_modulate(color(1.0, 1.0, 1.0, 0.0))
  
  # Connect close button
  let close_button = self.find("Close", Control)
  if ?close_button:
    self.bind_signal(close_button, ("pressed", "on_close"))
  
  # GD4: Re-enabled GUI input signal binding for focus management
  # Note: This will be handled in the gui_input method below
  
  print("[UI] Console initialization complete - Tween animations enabled, state flags watched")

proc watch_states(self: Console) =
  # Watch for local flag changes
  state.local_flags.changes:
    if ConsoleVisible.added:
      self.show_console()
    elif ConsoleVisible.removed:
      self.hide_console()
    elif CommandMode.added:
      self.ghost()
    elif CommandMode.removed:
      self.unghost()
    
    if MouseCaptured.added:
      # GD4: Fixed mouse filter enum
      self.set_mouse_filter(mouseFilterIgnore)
    elif MouseCaptured.removed:
      self.set_mouse_filter(Control_MouseFilter(self.default_mouse_filter))
  
  # Watch for console log changes
  state.console.log.changes:
    if added:
      # Append new log entry with BBCode formatting
      self.append_text(change.item)
    elif removed:
      # Clear and rebuild entire log
      self.clear()
      let full_log = state.console.log.value.join("\n")
      if full_log.len > 0:
        self.append_text(full_log)
      break

proc on_close(self: Console) =
  # Close console and remove focus
  state.pop_flags(ConsoleVisible, ConsoleFocused)

method gui_input*(self: Console, event: gdref InputEvent) {.gdsync.} =
  # Handle GUI input for focus management
  if event[] of InputEventMouseButton:
    debug "pushing ConsoleFocused", topics = "state"
    state.push_flag ConsoleFocused

method unhandled_input*(self: Console, event: gdref InputEvent) {.gdsync.} =
  # Handle escape key to close console
  if ConsoleFocused in state.local_flags and event[].is_action_pressed("ui_cancel"):
    # Don't handle joypad input if in command mode
    if not (event[] of InputEventJoypadButton) or CommandMode notin state.local_flags:
      state.pop_flags(ConsoleVisible, ConsoleFocused)
      # GD4: Fixed input handling method
      self.get_viewport().setInputAsHandled()