import gdext
import
  gdext/classes/[
    gdrichtextlabel, gdcontrol, gdnode, gdinputevent, gdinputeventjoypadbutton,
    gdinputeventmousebutton, gdvscrollbar, gdtween, gdviewport, gdmethodtweener,
  ]
# GD4: Fixed Tween import (was SceneTreeTween in Godot 3)
import core, gdcore, types, models/states
import std/strutils

type Console* {.gdsync.} =
  ptr object of RichTextLabel
    default_mouse_filter: int64
    tween: gdref Tween

proc watch_states(self: Console)

proc offset_x*(self: Console, offset: float) {.gdsync.} =
  # Move console horizontally based on offset (-1.0 = off-screen left, 0.0 = visible)
  let width = self.get_size().x
  let new_position = vector2(width * offset, self.get_position().y)
  self.set_position(new_position)

proc show_console(self: Console) =
  print("[UI] Console showing...")

  # Start console off-screen (hidden to the left)
  self.offset_x(-1.0) # Start off-screen
  self.set_visible(true)

  # Create tween for smooth slide-in animation (from left)
  if ?self.tween:
    self.tween[].kill()
  self.tween = self.create_tween()
  assert ?self.tween, "Failed to create tween for console animation"

  # Slide in from left with proper EXPO easing
  let tweener = self.tween[].tween_method(
    callable(self, new_string_name("offset_x")),
    variant(-1.0),
    variant(0.0),
    animation_duration,
  )
  discard tweener[].setTrans(transExpo)
  discard tweener[].setEase(easeInOut)
  print("[UI] Console opened with slide-in animation (EXPO/EASE_IN_OUT)")

proc hide_console(self: Console) =
  print("[UI] Console hiding...")

  # Reset position and animate slide-out
  self.set_position(vector2(0, self.get_position().y))

  # Create tween for smooth slide-out animation (to left)
  if ?self.tween:
    self.tween[].kill() # Kill existing tween
  self.tween = self.create_tween()
  assert ?self.tween, "Failed to create tween for console animation"

  # Slide out to the left with proper EXPO easing
  let tweener = self.tween[].tween_method(
    callable(self, new_string_name("offset_x")),
    variant(0.0),
    variant(-1.0),
    animation_duration,
  )
  discard tweener[].setTrans(transExpo)
  discard tweener[].setEase(easeInOut)
  # Hide console after animation completes
  discard self.tween[].tween_callback(
    callable(self, new_string_name("set_visible")).bind(variant(false))
  )
  print("[UI] Console closed with slide-out animation (EXPO/EASE_IN_OUT)")

method ready*(self: Console) {.gdsync.} =
  print(
    "[UI] Console ready - Godot 4 migration complete with animations and state watching"
  )

  # Store default mouse filter
  self.default_mouse_filter = int64(self.get_mouse_filter())

  # Set console height to 1/3 of screen height
  let viewport = self.get_viewport()
  if ?viewport:
    let screen_height = viewport.get_visible_rect().size.y
    let console_height = screen_height / 3.0
    self.set_custom_minimum_size(vector2(400, console_height))
    print("[UI] Console height set to 1/3 screen height: " & $console_height)

  # GD4: Re-enabled state watching
  self.watch_states()

  # Set initial visibility - start hidden
  if ConsoleVisible notin state.local_flags:
    self.set_visible(false)

  # Modulation disabled - scrollbar remains visible
  # # Configure scrollbar appearance
  # for i in 0 ..< self.get_child_count():
  #   let child = self.get_child(i)
  #   if child of VScrollBar:
  #     let scrollbar = child.as(VScrollBar)
  #     scrollbar.set_modulate(color(1.0, 1.0, 1.0, 0.0))

  # Connect close button
  let close_button = self.find("Close", Control)
  if ?close_button:
    discard close_button.connect("pressed", self.callable("_on_close"))
    print("[UI] Console close button connected to signal handler")

  # GD4: Re-enabled GUI input signal binding for focus management
  # Note: This will be handled in the gui_input method below

  print(
    "[UI] Console initialization complete - Tween animations enabled, state flags watched"
  )

proc watch_states(self: Console) =
  # Watch for local flag changes
  state.local_flags.changes:
    if ConsoleVisible.added:
      self.show_console()
    elif ConsoleVisible.removed:
      self.hide_console()
    # Ghosting disabled - no visual changes for command mode
    # elif CommandMode.added:
    #   self.ghost()
    # elif CommandMode.removed:
    #   self.unghost()

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

proc on_close(self: Console) {.gdsync, name: "_on_close".} =
  # Close console and remove focus
  print("[UI] Console close button pressed")
  state.pop_flags(ConsoleVisible, ConsoleFocused)

method gui_input*(self: Console, event: gdref InputEvent) {.gdsync.} =
  if event[] of InputEventMouseButton:
    debug "pushing ConsoleFocused", topics = "state"
    state.push_flags ConsoleFocused

method unhandled_input*(self: Console, event: gdref InputEvent) {.gdsync.} =
  if ConsoleFocused in state.local_flags and
      event[].is_action_pressed("ui_cancel"):
    if not (event[] of InputEventJoypadButton) or
        CommandMode notin state.local_flags:
      state.pop_flags ConsoleVisible, ConsoleFocused
      self.get_viewport().set_input_as_handled()
