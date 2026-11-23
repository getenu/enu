import std/[strutils, tables]
import pkg/[godot]
import pkg/compiler/[lineinfos]
import
  godotapi/[
    text_edit, scene_tree, node, input_event, global_constants, input_event_key,
    style_box_flat, gd_os, tween, scene_tree_tween, property_tweener,
    method_tweener, input, input_event_screen_touch,
  ]
import core, gdutils
import models except Color

const clear = init_color(0.0, 0.0, 0.0, 0.0)

proc configure_highlighting*(self: TextEdit) =
  # strings
  self.add_color_region("\"", "\"", IR_BLACK[TEXT], false)
  self.add_color_region("\"\"\"", "\"\"\"", IR_BLACK[TEXT], false)
  # block comments
  self.add_color_region("#[", "]#", IR_BLACK[COMMENT], false)
  # line comments
  self.add_color_region("#", "\n", IR_BLACK[COMMENT], true)

gdobj Editor of MarginContainer:
  var
    comment_color* {.gdExport.} = init_color(0.5, 0.5, 0.5)
    og_bg_color: Color
    tween: SceneTreeTween
    scroll_bar: VScrollBar
    text_edit: TextEdit
    left_panel: Container

  proc indent_new_line() =
    let editor = self.text_edit
    let column = int editor.cursor_get_column - 1
    if column > 0:
      let
        line = editor.get_line(editor.cursor_get_line)[0 .. column]
        stripped = line.strip

      if stripped.high > 0:
        let last = stripped[stripped.high]

        var spaces = line.indentation
        if (stripped in ["var", "let", "const", "type"]) or last in [':', '=']:
          spaces += 2

        editor.insert_text_at_cursor("\n" & " ".repeat(spaces))
        self.get_tree.set_input_as_handled()
      elif stripped.len == 0 and line.len > 0:
        editor.insert_text_at_cursor("\n" & line)
        self.get_tree.set_input_as_handled()

  method input*(event: InputEvent) =
    if event of InputEventKey and EDITOR_FOCUSED in state.local_flags:
      let event = event.as(InputEventKey)
      if not event.pressed:
        return
      if event.scancode == KEY_ENTER and host_os != "ios":
        self.indent_new_line()
      if event.scancode == KEY_SEMICOLON and state.config.semicolon_as_colon:
        self.text_edit.insert_text_at_cursor(":")
        self.get_tree.set_input_as_handled()
      elif event.scancode == KEY_HOME:
        self.text_edit.cursor_set_column(0)
        self.get_tree.set_input_as_handled()
      elif event.scancode == KEY_END:
        self.text_edit.cursor_set_column self.text_edit.get_line(
          self.text_edit.cursor_get_line
        ).len
        self.get_tree.set_input_as_handled()

  method gui_input*(event: InputEvent) =
    self.ignore_touches(event)

  method unhandled_input*(event: InputEvent) =
    if EDITOR_FOCUSED in state.local_flags and
        event.is_action_pressed("ui_cancel"):
      if not (event of InputEventJoypadButton) or
          COMMAND_MODE notin state.local_flags:
        # only push code (and so save + re-run the script) if it changed
        if self.text_edit.text != state.player.coding.code.nim:
          state.player.coding.code = Code.init(self.text_edit.text)
        state.player.coding = nil
        self.get_tree().set_input_as_handled()

  proc clear_errors() =
    for i in 0 ..< self.text_edit.get_line_count():
      self.text_edit.set_line_as_marked(i, false)

  proc highlight_errors() =
    self.text_edit.clear_executing_line()
    if ?state.player.coding:
      for err in state.player.coding.errors:
        self.text_edit.set_line_as_marked(int64(err.info.line - 1), true)

  proc `executing_line=`*(line: int) =
    if self.text_edit.get_line_count >= line and line >= 0:
      self.text_edit.set_executing_line(line)
    else:
      self.text_edit.clear_executing_line()

  method on_text_changed*() =
    state.player.open_code = self.text_edit.text

  method on_cursor_changed*() =
    state.player.cursor_position =
      (int self.text_edit.cursor_get_line, int self.text_edit.cursor_get_column)

  method set_opacity*(opacity: float) {.gdexport.} =
    self.opacity = opacity

  method offset_x*(offset: float) {.gdexport.} =
    let width = self.rect_size.x
    self.rect_position = vec2(width * offset, self.rect_position.y)

  method ghost*() {.gdexport.} =
    self.text_edit.ghost()
    self.mouse_filter = MOUSE_FILTER_PASS

  method unghost*() {.gdexport.} =
    self.text_edit.unghost()
    self.text_edit.mouse_filter = MOUSE_FILTER_PASS
    self.mouse_filter = MOUSE_FILTER_STOP

  proc close_editor() =
    self.text_edit.release_focus()
    self.rect_position = vec2(0, 0)
    if ?self.tween:
      self.tween.kill
    self.tween = self.get_tree.create_tween()
    discard self.tween
      .tween_method(
        self, "_offset_x", 0.0.to_variant, -1.0.to_variant, animation_duration
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)
    discard self.tween.tween_callback(
      self, "set_visible", new_array(false.to_variant)
    )

  method open_done() =
    state.pop_flag EDITOR_CLOSING

  proc open_editor() =
    self.opacity = 0.0
    if ?self.tween:
      self.tween.kill
    self.tween = self.get_tree.create_tween()
    self.visible = true
    discard
      self.tween.tween_callback(self, "_offset_x", new_array(0.0.to_variant))
    discard self.tween.tween_property(self, "modulate:a", 1.0.to_variant, 0.0)
    if COMMAND_MODE in state.local_flags:
      discard self.tween.tween_callback(self.text_edit, "_ghost")
    discard self.tween
      .tween_method(
        self, "_offset_x", -1.0.to_variant, 0.0.to_variant, animation_duration
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)
    discard self.tween.tween_callback(self, "_open_done")

  proc watch_open_thing() =
    var line_zid, code_zid: EID
    state.player.coding_value.changes:
      if removed:
        let thing = state.player.coding
        if thing.is_nil:
          Ed.thread_ctx.untrack(line_zid)
          Ed.thread_ctx.untrack(code_zid)
          self.close_editor()
          state.player.open_code = ""
        else:
          self.open_editor()
          line_zid = thing.current_line_value.changes:
            if added:
              # only update the executing line if the code hasn't been changed.
              if self.text_edit.text == state.player.coding.code.nim:
                self.executing_line = change.item - 1
              else:
                self.text_edit.clear_executing_line()

          code_zid = thing.code_value.changes:
            if added or touched:
              let new_code = change.item.nim
              if new_code != "" and new_code != self.text_edit.text:
                self.text_edit.text = new_code
                state.player.open_code = new_code

          self.text_edit.text = state.player.coding.code.nim
          state.player.open_code = self.text_edit.text

          if COMMAND_MODE in state.local_flags:
            self.ghost()
          else:
            self.unghost()
          self.clear_errors()
          self.highlight_errors()
          let line = thing.current_line - 1
          self.executing_line = line

  proc watch_local_flags() =
    state.local_flags.changes:
      if FULL_WIDTH_PANELS.added:
        self.left_panel.anchor_right = 1.0
        self.left_panel.margin_right = 0.0
      elif FULL_WIDTH_PANELS.removed:
        self.left_panel.margin_right = -1.0
        self.left_panel.anchor_right = 0.5

      if CONSOLE_VISIBLE.added:
        self.highlight_errors()
      elif CONSOLE_VISIBLE.removed:
        self.clear_errors()
      elif EDITOR_FOCUSED.added:
        self.text_edit.grab_focus
        self.left_panel.raisee()
      if COMMAND_MODE.added:
        if EDITOR_VISIBLE in state.local_flags:
          state.player.coding.code = Code.init(self.text_edit.text)

          self.ghost()
          self.text_edit.release_focus()
          self.mouse_filter = MOUSE_FILTER_IGNORE
      elif COMMAND_MODE.removed:
        if EDITOR_VISIBLE in state.local_flags:
          self.unghost()
          self.text_edit.grab_focus()
          self.mouse_filter = MOUSE_FILTER_STOP

  proc watch() =
    self.watch_open_thing()
    self.watch_local_flags()

  method ready*() =
    self.text_edit = find("TextEdit", TextEdit)
    self.left_panel = state.nodes.game.find("LeftPanel", Container)
    self.bind_signals(self.text_edit, "text_changed", "cursor_changed")
    state.nodes.game.bind_signal(self, "gui_input", self.name)

    for name in ["Close", "Run"]:
      let control = find(name, Control)
      self.bind_signal(control, ("pressed", name.to_lower))
      self.bind_signal(control, ("gui_input", "child_focused"))
    var stylebox = self.text_edit.get_stylebox("normal").as(StyleBoxFlat)
    self.og_bg_color = stylebox.bg_color

    self.text_edit.configure_highlighting()

    # hide verticle scrollbar. Should be restyled and re-enabled in the future.
    for child in self.text_edit.get_children():
      let o = child.as_object(Node) as VScrollBar
      if ?o:
        self.scroll_bar = o
        o.modulate = clear
    assert ?self.scroll_bar
    self.watch()

  method on_close() =
    if ?state.player.coding:
      if self.text_edit.text != state.player.coding.code.nim:
        state.player.coding.code = Code.init(self.text_edit.text)
      state.player.coding = nil

  method on_run() =
    if ?state.player.coding:
      state.player.coding.code = Code.init("")
      state.player.coding.code = Code.init(self.text_edit.text)

  method on_child_focused(event: InputEvent) =
    self.grab_focus()
