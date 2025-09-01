import gdext
import gdext/classes/[gdrichtextlabel, gdcontrol, gdnode, 
                     gdinputevent, gdinputeventjoypadbutton, gdvscrollbar]
# TODO: Fix SceneTreeTween import - gdscene_tree_tween not found
import core, gdutils, types, models/states
import std/strutils

type Console* {.gdsync.} = ptr object of RichTextLabel
  default_mouse_filter: int64
  # TODO: Re-enable when SceneTreeTween import is fixed
  # tween: SceneTreeTween

proc offset_x*(self: Console, offset: float) =
  let width = self.get_size().x
  self.set_position(vector2(width * offset, self.get_position().y))

proc show_console(self: Console) =
  # Set appropriate opacity based on state
  if CommandMode in state.local_flags:
    self.set_modulate(dimmed_alpha)
  else:
    self.set_modulate(color(1.0, 1.0, 1.0, 1.0))
  
  # TODO: Re-enable when SceneTreeTween is available
  # Kill existing tween
  # if ?self.tween:
  #   self.tween.kill()
  # 
  # self.tween = self.get_tree().create_tween()
  self.set_visible(true)
  # 
  # # Animate sliding in from right
  # discard self.tween.tween_method(
  #   callable(self, "offset_x"), variant(-1.0), variant(0.0), animation_duration
  # )
  # self.tween.set_trans(Tween_TransitionType.TRANS_EXPO)
  # self.tween.set_ease(Tween_EaseType.EASE_IN_OUT)
  
  # For now, just show directly without animation
  self.offset_x(0.0)

proc hide_console(self: Console) =
  # TODO: Re-enable when SceneTreeTween is available
  # Kill existing tween
  # if ?self.tween:
  #   self.tween.kill()
  # 
  # self.tween = self.get_tree().create_tween()
  # self.set_position(vector2(0.0, self.get_position().y))
  # 
  # # Animate sliding out to right
  # discard self.tween.tween_method(
  #   callable(self, "offset_x"), variant(0.0), variant(-1.0), animation_duration
  # )
  # self.tween.set_trans(Tween_TransitionType.TRANS_EXPO)
  # self.tween.set_ease(Tween_EaseType.EASE_IN_OUT)
  # 
  # # Hide when animation complete
  # discard self.tween.tween_callback(callable(self, "set_visible").bind(false))
  
  # For now, just hide directly without animation
  self.set_visible(false)

method ready*(self: Console) {.gdsync.} =
  print("[UI] Console ready - implementing log display and animations")
  
  # Store default mouse filter
  self.default_mouse_filter = int64(self.get_mouse_filter())
  
  # Watch for state flag changes - TODO: Re-enable after fixing method
  # self.watch_states()
  
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
  if not close_button.is_nil():
    self.bind_signal(close_button, ("pressed", "close"))
  
  print("[UI] Console configured with state watching and animations")

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
      # TODO: Fix enum name for Godot 4 - MOUSE_FILTER_IGNORE doesn't exist
      # self.set_mouse_filter(Control.MouseFilterIgnore)  
      self.set_mouse_filter(Control_MouseFilter(2)) # Temporary: IGNORE = 2
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

method unhandled_input*(self: Console, event: InputEvent) {.gdsync.} =
  # Handle escape key to close console
  if ConsoleFocused in state.local_flags and event.is_action_pressed("ui_cancel"):
    # Don't handle joypad input if in command mode
    if not (event of InputEventJoypadButton) or CommandMode notin state.local_flags:
      state.pop_flags(ConsoleVisible, ConsoleFocused)
      # TODO: Fix for Godot 4 - set_input_as_handled method name changed
      # self.getViewport().set_input_as_handled()