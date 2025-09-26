import std/[strutils, tables, monotimes]
import gdext
import
  gdext/classes/[
    gdmargincontainer, gdcodeedit, gdinputevent, gdinputeventkey,
    gdinputeventmousebutton, gdcontrol, gdnode, gdvscrollbar, gdtween,
    gdstyleboxflat, gdbutton, gdinput, gdviewport, gdmethodtweener,
  ]
import core, gdcore, types, models/[states, units]
# import nim_highlighter  # GD4: Re-enable when CodeHighlighter API is fixedxx

type EnuEditor* {.gdsync.} =
  ptr object of MarginContainer
    code_edit*: CodeEdit
    # scroll_container: ScrollContainer
    left_panel: Control
    tween: gdref Tween
    og_bg_color: Color
    selection_color: Color
    caret_color: Color

proc configure_highlighting*(self: EnuEditor) =
  # Configure syntax highlighting for Nim - Godot 4 version
  let code_edit = self.code_edit

  # Enable basic code editing features
  code_edit.set_draw_line_numbers(true)
  code_edit.set_draw_tabs(true)
  code_edit.set_draw_spaces(false)

  # GD4: Set up Nim syntax highlighting with ir_black colors
  # TODO: Fix CodeHighlighter method signatures in gdext
  # Tried: result.highlighter.addKeywordColor(keyword.gdstring, color)
  # Error: type mismatch - expects method call syntax but generates function call
  # let nim_hl = create_nim_highlighter()
  # if not nim_hl.highlighter.is_nil:
  #   code_edit.set_syntax_highlighter(nim_hl.highlighter)
  #   print("[UI] Applied Nim syntax highlighting with ir_black colors")
  # else:
  #   print("[UI] Warning: Could not apply syntax highlighting - highlighter is nil")
  print("[UI] Nim syntax highlighting temporarily disabled for build fix")
  # Enable line folding
  code_edit.set_line_folding_enabled(true)
  code_edit.set_draw_fold_gutter(true)

  # Enable gutters for debugging features
  code_edit.set_draw_bookmarks_gutter(true) # For error highlighting
  code_edit.set_draw_executing_lines_gutter(true) # For execution tracking

  # Add color regions for syntax highlighting (equivalent to Godot 3)
  # Strings
  code_edit.add_string_delimiter("\"", "\"", false)
  code_edit.add_string_delimiter("\"\"\"", "\"\"\"", false)
  # Comments
  code_edit.add_comment_delimiter("#", "", true) # Line comments
  code_edit.add_comment_delimiter("#[", "]#", false) # Block comments

proc get_text*(self: EnuEditor): string =
  return $self.code_edit.get_text()

proc set_text*(self: EnuEditor, text: string) =
  self.code_edit.set_text(text)

proc clear_errors(self: EnuEditor) =
  # Clear all bookmarked lines (used for error marking)
  for i in 0 ..< self.code_edit.get_line_count():
    if self.code_edit.is_line_bookmarked(int32(i)):
      self.code_edit.set_line_as_bookmarked(int32(i), false)

proc highlight_errors(self: EnuEditor) =
  # Use bookmarks to mark error lines
  if ?state.open_unit:
    for err in state.open_unit.errors:
      self.code_edit.set_line_as_bookmarked(int32(err.info.line - 1), true)
      print("[UI] Editor marked error line: ", err.info.line - 1)

proc set_executing_line(self: EnuEditor, line: int) =
  # Clear all executing lines first
  self.code_edit.clear_executing_lines()

  # Set the new executing line if valid
  if self.code_edit.get_line_count() >= line and line >= 0:
    self.code_edit.set_line_as_executing(int32(line), true)
    print("[UI] Editor executing line set to: ", line)

proc offset_x(self: EnuEditor, offset: float) {.gdsync.} =
  # Move editor horizontally based on offset (-1.0 = off-screen left, 0.0 = visible)
  let width = self.get_size().x
  let new_position = vector2(width * offset, self.get_position().y)
  self.set_position(new_position)

proc open_editor(self: EnuEditor) =
  print("[UI] Editor opening...")

  # Start editor off-screen (hidden to the left)
  self.set_modulate(gdext.color(1.0, 1.0, 1.0, 0.0))
  self.offset_x(-1.0)  # Start off-screen
  self.set_visible(true)

  # Create tween for smooth slide-in animation (matches Godot 3 behavior)
  self.tween = self.create_tween()
  assert ?self.tween, "Failed to create tween for editor animation"

  # Immediate fade in (like Godot 3 tween_property with 0.0 duration)
  discard self.tween[].tween_property(
    self, new_node_path("modulate:a"), variant(1.0), 0.0
  )
  # Slide in from left with proper EXPO easing
  let tweener = self.tween[].tween_method(
    callable(self, new_string_name("offset_x")),
    variant(-1.0),
    variant(0.0),
    animation_duration
  )
  discard tweener[].setTrans(transExpo)
  discard tweener[].setEase(easeInOut)
  print("[UI] Editor opened with slide-in animation (EXPO/EASE_IN_OUT)")

proc close_editor(self: EnuEditor) =
  print("[UI] Editor closing...")
  if not self.code_edit.is_nil:
    self.code_edit.release_focus()

  # Reset position and animate slide-out
  self.set_position(vector2(0, self.get_position().y))

  # Create tween for smooth slide-out animation (matches Godot 3 behavior)
  if ?self.tween:
    self.tween[].kill()  # Kill existing tween
  self.tween = self.create_tween()
  assert ?self.tween, "Failed to create tween for editor animation"

  # Slide out to the left with proper EXPO easing
  let tweener = self.tween[].tween_method(
    callable(self, new_string_name("offset_x")),
    variant(0.0),
    variant(-1.0),
    animation_duration
  )
  discard tweener[].setTrans(transExpo)
  discard tweener[].setEase(easeInOut)
  # Hide editor after animation completes
  discard self.tween[].tween_callback(
    callable(self, new_string_name("set_visible")).bind(variant(false))
  )
  print("[UI] Editor closed with slide-out animation (EXPO/EASE_IN_OUT)")

proc watch_open_unit(self: EnuEditor) =
  var line_zid: ZID
  state.open_unit_value.changes:
    if removed:
      let unit = state.open_unit
      if unit.is_nil:
        Zen.thread_ctx.untrack(line_zid)
        self.close_editor()
        # TODO: Set open_code on player when field is available
        # if ?state.player:
        #   state.player.open_code = ""
      else:
        print("[UI] Editor opening for unit: ", unit.id)
        self.open_editor()
        line_zid = unit.current_line_value.changes:
          if added:
            # Only update the executing line if the code hasn't been changed
            # TODO: Fix string comparison for Godot 4 String vs nim string
            # if string(self.code_edit.get_text()) == state.open_unit.code.nim:
            self.set_executing_line(change.item - 1)
            # else:
            #   self.code_edit.clear_executing_line()  # TODO: Implement method

        self.code_edit.set_text(state.open_unit.code.nim)
        # TODO: Set open_code on player when field is available
        # if ?state.player:
        #   state.player.open_code = self.code_edit.get_text()

        self.clear_errors()
        self.highlight_errors()
        let line = unit.current_line - 1
        self.set_executing_line(line)

proc watch_local_flags(self: EnuEditor) =
  state.local_flags.changes:
    if EditorFocused.added:
      if not self.code_edit.is_nil:
        self.code_edit.grab_focus()
    elif CommandMode.added:
      if EditorVisible in state.local_flags and ?state.open_unit:
        # TODO: Fix Code.init with proper string conversion
        state.open_unit.code = Code.init($self.code_edit.get_text())
        # TODO: Ghost mode for command overlay
        # discard
    elif CommandMode.removed:
      if EditorVisible in state.local_flags:
        if not self.code_edit.is_nil:
          self.code_edit.grab_focus()

proc watch_states(self: EnuEditor) =
  self.watch_open_unit()
  self.watch_local_flags()

method ready*(self: EnuEditor) {.gdsync.} =
  print("[UI] Editor ready - using Godot 4 CodeEdit")

  # Find the CodeEdit node - this should always succeed if scene is properly set up
  self.code_edit = self.find("CodeEdit", CodeEdit)
  assert ?self.code_edit, "CodeEdit node not found in Editor scene"

  # Start hidden until opened
  self.set_visible(false)
  print("[UI] Editor initialized (hidden by default)")
  # Find other UI elements - some may not exist in current scene
  # self.scroll_container = self.find("ScrollContainer", ScrollContainer)
  if not state.nodes.game.is_nil:
    self.left_panel = state.nodes.game.find("LeftPanel", Control)
  else:
    print("[UI] Warning: state.nodes.game is nil, cannot find LeftPanel")

  # Initialize tween for smooth animations - restored for slide animation
  # Note: Tween will be created when needed, not here to avoid lifecycle issues

  # Get colors for UI state management
  self.selection_color =
    self.code_edit.get_theme_color("selection_color", "TextEdit")
  self.caret_color = self.code_edit.get_theme_color("caret_color", "TextEdit")

  # Configure the code editor
  self.configure_highlighting()

  # Connect signals for editor functionality
  if not self.code_edit.has_signal("text_changed"):
    self.code_edit.add_user_signal("text_changed")
  let text_changed_callable =
    callable(self, new_string_name("_on_text_changed"))
  discard self.code_edit.connect(
    new_string_name("text_changed"), text_changed_callable
  )

  if not self.code_edit.has_signal("caret_changed"):
    self.code_edit.add_user_signal("caret_changed")
  let caret_changed_callable =
    callable(self, new_string_name("_on_caret_changed"))
  discard self.code_edit.connect(
    new_string_name("caret_changed"), caret_changed_callable
  )

  # Connect button signals
  for name in ["Close", "Run"]:
    let control = self.find(name, Control)
    if ?control:
      let method_name = "on_" & name.to_lower
      let callable_obj = callable(self, new_string_name(method_name))
      discard control.connect(new_string_name("pressed"), callable_obj)
    else:
      print("[UI] Warning: Button '", name, "' not found in Editor scene")

  # GD4: Re-enabled GUI input focus management - handled in gui_input method

  # Start watching state changes
  self.watch_states()

  print("[UI] Editor configured with CodeEdit")

proc on_text_changed(self: EnuEditor) =
  # Handle text changes for auto-save, validation, etc.
  print("[UI] Editor text changed")
  # TODO: Connect to script compilation/validation system

proc on_caret_changed(self: EnuEditor) =
  # Handle caret position changes for status display
  let line = self.code_edit.get_caret_line()
  let column = self.code_edit.get_caret_column()
  print("[UI] Editor caret moved to line ", line, ", column ", column)

  # TODO: Set cursor position on player when field is available
  # if ?state.player:
  #   state.player.cursor_position = (int(line), int(column))

proc on_close(self: EnuEditor) {.gdsync.} =
  # Save code and close editor
  if ?state.open_unit:
    # TODO: Fix Code.init with proper string conversion
    state.open_unit.code = Code.init($self.code_edit.get_text())
    state.open_unit = nil

proc on_run(self: EnuEditor) {.gdsync.} =
  # Run the current code
  if ?state.open_unit:
    # TODO: Fix Code.init with proper string conversion
    state.open_unit.code = Code.init($self.code_edit.get_text())
    # TODO: Force code execution when Code.init is fixed
    # state.open_unit.code = Code.init(self.code_edit.get_text())



proc indent_new_line*(self: EnuEditor) =
  # Smart indentation for new lines - simplified for compilation
  # TODO: Implement proper indentation when string conversion is fixed
  self.code_edit.insert_text_at_caret("\n")

method unhandled_input*(self: EnuEditor, event: gdref InputEvent) {.gdsync.} =
  # Handle editor-specific input events
  if EditorFocused in state.local_flags and
      event[].is_action_pressed("ui_cancel"):
    # Escape key - save and close editor
    if ?state.open_unit:
      # TODO: Fix Code.init with proper string conversion
      state.open_unit.code = Code.init($self.code_edit.get_text())
      state.open_unit = nil
    self.get_viewport().set_input_as_handled()

method gui_input*(self: EnuEditor, event: gdref InputEvent) {.gdsync.} =
  # Handle GUI input for focus management first
  if event[] of InputEventMouseButton:
    debug "pushing EditorFocused", topics = "state"
    state.push_flag EditorFocused

  # Handle GUI input for the editor
  if event[] of InputEventKey and EditorFocused in state.local_flags:
    let key_event = event[].as(InputEventKey)
    if not key_event.is_pressed():
      return

    case key_event.get_keycode()
    of keyEnter:
      # Smart indentation on Enter
      self.indent_new_line()
      self.get_viewport().set_input_as_handled()
    of keySemicolon:
      # Optional: semicolon as colon for Logo-style syntax
      if state.config.semicolon_as_colon:
        self.code_edit.insert_text_at_caret(":")
        self.get_viewport().set_input_as_handled()
    of keyHome:
      # Go to beginning of line
      self.code_edit.set_caret_column(0'i32)
      self.get_viewport().set_input_as_handled()
    of keyEnd:
      # Go to end of line
      let current_line = self.code_edit.get_caret_line()
      let line_text = self.code_edit.get_line(current_line)
      self.code_edit.set_caret_column(int32(line_text.length()))
      self.get_viewport().set_input_as_handled()
    else:
      # Handle all other keys - do nothing for now
      discard
