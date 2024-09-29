import std/[strutils, tables]
import pkg/[godot]
import pkg/compiler/[lineinfos]
import
  godotapi/[
    text_edit, scene_tree, node, input_event, global_constants, input_event_key,
    style_box_flat, gd_os, tween, scene_tree_tween, property_tweener,
    method_tweener, input
  ]
import core, gdutils
import models except Color

proc configure_highlighting*(self: TextEdit) =
  # strings
  self.add_color_region("\"", "\"", ir_black[text], false)
  self.add_color_region("\"\"\"", "\"\"\"", ir_black[text], false)
  # block comments
  self.add_color_region("#[", "]#", ir_black[comment], false)
  # line comments
  self.add_color_region("#", "\n", ir_black[comment], true)

gdobj Editor of MarginContainer:
  var
    comment_color* {.gdExport.} = init_color(0.5, 0.5, 0.5)
    og_bg_color: Color
    tween: SceneTreeTween
    scroll_bar: VScrollBar
    text_edit: TextEdit

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
    var event = event.as(InputEventKey)
    if not event.is_nil and event.pressed:
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

  method unhandled_input*(event: InputEvent) =
    if EditorFocused in state.local_flags and
        event.is_action_pressed("ui_cancel"):
      if not (event of InputEventJoypadButton) or
          CommandMode notin state.local_flags:
        state.open_unit.code = Code.init(self.text_edit.text)
        state.open_unit = nil
        self.get_tree().set_input_as_handled()

  proc clear_errors() =
    for i in 0 ..< self.text_edit.get_line_count():
      self.text_edit.set_line_as_marked(i, false)

  proc highlight_errors() =
    self.text_edit.clear_executing_line()
    if ?state.open_unit:
      for err in state.open_unit.errors:
        self.text_edit.set_line_as_marked(int64(err.info.line - 1), true)

  proc `executing_line=`*(line: int) =
    if self.text_edit.get_line_count >= line and line >= 0:
      self.text_edit.set_executing_line(line)
    else:
      self.text_edit.clear_executing_line()

  method on_text_changed*() =
    state.player.open_code = self.text_edit.text

  method on_cursor_changed*() =
    state.player.cursor_position = (
      int self.text_edit.cursor_get_line, int self.text_edit.cursor_get_column
    )

  method set_opacity*(opacity: float) {.gdexport.} =
    self.opacity = opacity

  method offset_x*(offset: float) {.gdexport.} =
    let width = self.rect_size.x
    self.rect_position = vec2(width * offset, self.rect_position.y)

  method ghost*() {.gdexport.} =
    self.text_edit.ghost()

  method unghost*() {.gdexport.} =
    self.text_edit.unghost()
    self.text_edit.mouse_filter = MOUSE_FILTER_PASS

  proc close_editor() =
    self.text_edit.release_focus()
    self.rect_position = vec2(0, 0)
    if ?self.tween:
      self.tween.kill
    self.tween = self.get_tree.create_tween()
    discard
      self.tween
      .tween_method(
        self, "_offset_x", 0.0.to_variant, -1.0.to_variant, animation_duration
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)
    discard self.tween.tween_callback(
      self, "set_visible", new_array(false.to_variant)
    )

  proc open_editor() =
    self.opacity = 0.0
    if ?self.tween:
      self.tween.kill
    self.tween = self.get_tree.create_tween()
    self.visible = true
    discard
      self.tween.tween_callback(self, "_offset_x", new_array(0.0.to_variant))
    discard self.tween.tween_property(self, "modulate:a", 1.0.to_variant, 0.0)
    if CommandMode in state.local_flags:
      discard self.tween.tween_callback(self.text_edit, "_ghost")
    discard
      self.tween
      .tween_method(
        self, "_offset_x", -1.0.to_variant, 0.0.to_variant, animation_duration
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)

  proc watch_open_unit() =
    var line_zid: ZID
    state.open_unit_value.changes:
      if removed:
        let unit = state.open_unit
        if unit.is_nil:
          Zen.thread_ctx.untrack(line_zid)
          self.close_editor()
          state.player.open_code = ""
        else:
          self.open_editor()
          line_zid = unit.current_line_value.changes:
            if added:
              # only update the executing line if the code hasn't been changed.
              if self.text_edit.text == state.open_unit.code.nim:
                self.executing_line = change.item - 1
              else:
                self.text_edit.clear_executing_line()

          self.text_edit.text = state.open_unit.code.nim
          state.player.open_code = self.text_edit.text

          if CommandMode in state.local_flags:
            self.ghost()
          else:
            self.unghost()
          self.clear_errors()
          self.highlight_errors()
          let line = unit.current_line - 1
          self.executing_line = line

  proc watch_local_flags() =
    state.local_flags.changes:
      if ConsoleVisible.added:
        self.highlight_errors()
      elif ConsoleVisible.removed:
        self.clear_errors()
      elif EditorFocused.added:
        self.text_edit.grab_focus
      if CommandMode.added:
        if EditorVisible in state.local_flags:
          state.open_unit.code = Code.init(self.text_edit.text)

          self.ghost()
          self.text_edit.release_focus()
      elif CommandMode.removed:
        if EditorVisible in state.local_flags:
          self.unghost()
          self.text_edit.grab_focus()

  proc watch() =
    self.watch_open_unit()
    self.watch_local_flags()

  method ready*() =
    self.text_edit = find("TextEdit", TextEdit)
    self.bind_signals(self.text_edit, "text_changed", "cursor_changed")
    # self.text_edit.bind_signal(self, "gui_input")
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
        o.modulate = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.0)
    assert ?self.scroll_bar
    self.watch()

  proc content_height(): int =
    let line_height = self.text_edit.get_line_height
    for line in 0 ..< self.text_edit.get_line_count:
      result += int(
        (self.text_edit.get_line_wrap_count(line) + 1) * line_height
      )

  method process(delta: float) =
    self.text_edit.rect_min_size =
      vec2(self.rect_size.x, max(float self.content_height, self.rect_size.y))
    self.text_edit.rect_size = self.text_edit.rect_min_size

  method on_close() =
    if ?state.open_unit:
      state.open_unit.code = Code.init(self.text_edit.text)
      state.open_unit = nil

  method on_run() =
    if ?state.open_unit:
      state.open_unit.code = Code.init("")
      state.open_unit.code = Code.init(self.text_edit.text)

  method on_child_focused(event: InputEvent) =
    self.grab_focus()
