import std/[strutils, tables]
import pkg/[godot]
import pkg/compiler/[lineinfos]
import
  godotapi/[
    text_edit, scene_tree, node, input_event, global_constants, input_event_key,
    style_box_flat, gd_os
  ]
import core, globals
import models except Color

proc configure_highlighting*(self: TextEdit) =
  # strings
  self.add_color_region("\"", "\"", ir_black[text], false)
  self.add_color_region("\"\"\"", "\"\"\"", ir_black[text], false)
  # block comments
  self.add_color_region("#[", "]#", ir_black[comment], false)
  # line comments
  self.add_color_region("#", "\n", ir_black[comment], true)

gdobj Editor of TextEdit:
  var
    comment_color* {.gdExport.} = init_color(0.5, 0.5, 0.5)
    og_bg_color: Color

  proc indent_new_line() =
    let column = int self.cursor_get_column - 1
    if column > 0:
      let
        line = self.get_line(self.cursor_get_line)[0 .. column]
        stripped = line.strip()

      if stripped.high > 0:
        let last = $stripped[stripped.high]

        if (stripped in ["var", "let", "const", "type"]) or last in [":", "="]:
          let spaces = " ".repeat(line.indentation + 2)
          self.insert_text_at_cursor("\n" & spaces)
          self.get_tree.set_input_as_handled()

  method input*(event: InputEvent) =
    var event = event.as(InputEventKey)
    if not event.is_nil and event.pressed:
      if event.scancode == KEY_ENTER:
        self.indent_new_line()
      if event.scancode == KEY_SEMICOLON and state.config.semicolon_as_colon:
        self.insert_text_at_cursor(":")
        self.get_tree.set_input_as_handled()
      elif event.scancode == KEY_HOME:
        self.cursor_set_column(0)
        self.get_tree.set_input_as_handled()
      elif event.scancode == KEY_END:
        self.cursor_set_column self.get_line(self.cursor_get_line).len
        self.get_tree.set_input_as_handled()

  method unhandled_input*(event: InputEvent) =
    if EditorFocused in state.local_flags and
        event.is_action_pressed("ui_cancel"):
      if not (event of InputEventJoypadButton) or
          CommandMode notin state.local_flags:
        state.open_unit.code = Code.init(self.text)
        state.open_unit = nil
        self.get_tree().set_input_as_handled()

  proc clear_errors() =
    for i in 0 ..< self.get_line_count():
      self.set_line_as_marked(i, false)

  proc highlight_errors() =
    self.clear_executing_line()
    if ?state.open_unit:
      for err in state.open_unit.errors:
        self.set_line_as_marked(int64(err.info.line - 1), true)

  proc `executing_line=`*(line: int) =
    if self.get_line_count >= line and line >= 0:
      self.set_executing_line(line)
    else:
      self.clear_executing_line()

  method on_text_changed*() =
    state.player.open_code = self.text

  method on_cursor_changed*() =
    state.player.cursor_position =
      (int self.cursor_get_line, int self.cursor_get_column)

  method ready*() =
    self.bind_signals(self, "text_changed", "cursor_changed")
    var stylebox = self.get_stylebox("normal").as(StyleBoxFlat)
    self.og_bg_color = stylebox.bg_color

    state.local_flags.changes:
      if ConsoleVisible.added:
        self.highlight_errors()
      elif ConsoleVisible.removed:
        self.clear_errors()
      elif EditorFocused.added:
        self.grab_focus

    var line_zid: ZID
    state.open_unit_value.changes:
      if added:
        let unit = change.item
        if unit.is_nil:
          self.release_focus()
          self.visible = false
          state.player.open_code = ""
        else:
          line_zid =
            unit.current_line_value.changes:
              if added:
                # only update the executing line if the code hasn't been changed.
                if self.text == state.open_unit.code.nim:
                  self.executing_line = change.item - 1
                else:
                  self.clear_executing_line()
          self.visible = true
          self.text = state.open_unit.code.nim
          state.player.open_code = self.text

          if CommandMode in state.local_flags:
            self.modulate = dimmed_alpha
          else:
            self.modulate = solid_alpha
            self.grab_focus()
          self.clear_errors()
          self.highlight_errors()
          let line = unit.current_line - 1
          self.executing_line = line
      if removed:
        if ?change.item:
          Zen.thread_ctx.untrack(line_zid)

    state.local_flags.changes:
      if EditorFocused.added:
        self.grab_focus
      if CommandMode.added:
        if EditorVisible in state.local_flags:
          state.open_unit.code = Code.init(self.text)

          self.modulate = dimmed_alpha
          self.release_focus
      elif CommandMode.removed:
        if EditorVisible in state.local_flags:
          self.modulate = solid_alpha
          self.grab_focus

    self.configure_highlighting()
