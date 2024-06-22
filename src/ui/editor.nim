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

gdobj Editor of TextEdit:
  var
    comment_color* {.gdExport.} = init_color(0.5, 0.5, 0.5)
    og_bg_color: Color
    tween: SceneTreeTween

  proc indent_new_line() =
    let column = int self.cursor_get_column - 1
    if column > 0:
      let
        line = self.get_line(self.cursor_get_line)[0 .. column]
        stripped = line.strip()

      if stripped.high > 0:
        let last = $stripped[stripped.high]

        var spaces = line.indentation
        if (stripped in ["var", "let", "const", "type"]) or last in [":", "="]:
          spaces += 2

        self.insert_text_at_cursor("\n" & " ".repeat(spaces))
        self.get_tree.set_input_as_handled()

  method input*(event: InputEvent) =
    var event = event.as(InputEventKey)
    if not event.is_nil and event.pressed:
      if event.scancode == KEY_ENTER and host_os != "ios":
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
    state.player.cursor_position = (
      int self.cursor_get_line, int self.cursor_get_column
    )

  method set_opacity*(opacity: float) {.gdexport.} =
    self.opacity = opacity

  method offset_x*(offset: float) {.gdexport.} =
    let width = self.rect_size.x
    self.rect_position = vec2(width * offset, self.rect_position.y)

  method ghost_me*() {.gdexport.} =
    self.ghost()

  method ready*() =
    self.bind_signals(self, "text_changed", "cursor_changed")
    state.nodes.game.bind_signal(self, "gui_input", self.name)

    for name in ["Close", "Run"]:
      let control = find(name, Control)
      self.bind_signal(control, ("pressed", name.to_lower))
      self.bind_signal(control, ("gui_input", "child_focused"))

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
      if removed:
        let unit = state.open_unit
        if unit.is_nil:
          self.release_focus()
          self.rect_position = vec2(0, 0)
          if ?self.tween:
            self.tween.kill
          self.tween = self.get_tree.create_tween()
          discard
            self.tween
            .tween_method(
              self, "_offset_x", 0.0.to_variant, -1.0.to_variant,
              animation_duration
            )
            .set_trans(TRANS_EXPO)
            .set_ease(EASE_IN_OUT)
          discard self.tween.tween_callback(
            self, "set_visible", new_array(false.to_variant)
          )

          state.player.open_code = ""
        else:
          line_zid = unit.current_line_value.changes:
            if added:
              # only update the executing line if the code hasn't been changed.
              if self.text == state.open_unit.code.nim:
                self.executing_line = change.item - 1
              else:
                self.clear_executing_line()
          self.visible = true

          # self.rect_position = vec2(-960, 0)

          if change.item == nil:
            self.opacity = 0.0
            if ?self.tween:
              self.tween.kill
            self.tween = self.get_tree.create_tween()

            discard self.tween.tween_callback(
              self, "_offset_x", new_array(0.0.to_variant)
            )
            discard
              self.tween.tween_property(self, "modulate:a", 1.0.to_variant, 0.0)
            if CommandMode in state.local_flags:
              discard self.tween.tween_callback(self, "_ghost_me")
            discard
              self.tween
              .tween_method(
                self, "_offset_x", -1.0.to_variant, 0.0.to_variant,
                animation_duration
              )
              .set_trans(TRANS_EXPO)
              .set_ease(EASE_IN_OUT)

          # tween.interpolate_value(
          #   0.0.as_variant, 0.2.as_variant, 0.0, 0.2, TRANS_EXPO, EASE_IN_OUT
          # )
          self.text = state.open_unit.code.nim
          state.player.open_code = self.text

          if CommandMode in state.local_flags:
            self.ghost()
          else:
            self.unghost()
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

          self.ghost()
          self.release_focus
      elif CommandMode.removed:
        if EditorVisible in state.local_flags:
          self.unghost()
          self.grab_focus

    self.configure_highlighting()
    # hide verticle scrollbar. Should be restyled and re-enabled in the future.
    for child in self.get_children():
      let o = child.as_object(Node) as VScrollBar
      if ?o:
        o.modulate = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.0)

  method on_close() =
    if ?state.open_unit:
      state.open_unit.code = Code.init(self.text)
      state.open_unit = nil

  method on_run() =
    if ?state.open_unit:
      state.open_unit.code = Code.init("")
      state.open_unit.code = Code.init(self.text)

  method on_child_focused(event: InputEvent) =
    self.grab_focus()
