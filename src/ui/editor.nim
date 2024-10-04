import std/[strutils, tables]
import pkg/[godot]
import pkg/compiler/[lineinfos]
import
  godotapi/[
    text_edit, scene_tree, node, input_event, global_constants, input_event_key,
    style_box_flat, gd_os, tween, scene_tree_tween, property_tweener,
    method_tweener, input, scroll_container, input_event_screen_touch
  ]
import core, gdutils
import models except Color

type ScrollState = enum
  Idle
  Detecting
  Scrolling
  Selecting
  WaitingForSelection

const clear = init_color(0.0, 0.0, 0.0, 0.0)

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
    scroll_container: ScrollContainer
    adjust_scroll_next_frame: bool

    start_scroll: int64
    scroll_state = Idle
    selection_color: Color
    caret_color: Color
    selecting: bool
    selection_timer: MonoTime
    touch_timer: MonoTime

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
    if event of InputEventKey and not event.is_nil:
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
      self.adjust_scroll_next_frame = true
    elif event of InputEventScreenTouch:
      let event = event as InputEventScreenTouch
      if event.pressed:
        self.touch_timer = get_mono_time() + 0.5.seconds
      else:
        self.touch_timer = MonoTime.high
    elif event of InputEventScreenDrag and self.scroll_state == Idle:
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

  proc line_rect(
      line_num: int
  ): tuple[top_left: Vector2, bottom_right: Vector2] =
    let line_height = float self.text_edit.get_line_height
    for line in 1 ..< line_num:
      result.top_left.y +=
        (self.text_edit.get_line_wrap_count(line).float + 1) * line_height
    result.bottom_right = vec2(
      self.rect_size.x,
      result.top_left.y +
        (self.text_edit.get_line_wrap_count(line_num).float + 1) * line_height,
    )

  proc visible_window(): tuple[top_left: Vector2, bottom_right: Vector2] =
    let vscroll = float self.scroll_container.scroll_vertical
    result = (
      vec2(0.0, vscroll), vec2(self.rect_size.x, self.rect_size.y + vscroll)
    )

  proc scroll_to_cursor() =
    let rect = self.line_rect(self.text_edit.cursor_get_line + 1)
    let window = self.visible_window
    if rect.top_left.y <= window.top_left.y:
      self.scroll_container.scroll_vertical = int rect.top_left.y
    elif rect.bottom_right.y >= window.bottom_right.y:
      self.scroll_container.scroll_vertical =
        int(rect.bottom_right.y - self.rect_size.y)

  method on_text_changed*() =
    state.player.open_code = self.text_edit.text
    self.rescale

  method on_cursor_changed*() =
    state.player.cursor_position = (
      int self.text_edit.cursor_get_line, int self.text_edit.cursor_get_column
    )
    if self.text_edit.is_selection_active:
      self.scroll_to_cursor

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
    discard self.tween.tween_callback(self, "_rescale")

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

  proc content_height(): float =
    self.line_rect(self.text_edit.get_line_count).bottom_right.y

  method rescale() =
    self.text_edit.rect_min_size =
      vec2(self.rect_size.x, max(float self.content_height, self.rect_size.y))
    self.text_edit.rect_size = self.text_edit.rect_min_size
    self.scroll_to_cursor

  method ready*() =
    self.text_edit = find("TextEdit", TextEdit)
    self.caret_color = self.text_edit.get_color("caret_color")
    self.selection_color = self.text_edit.get_color("selection_color")
    self.scroll_container = find("ScrollContainer", ScrollContainer)
    self.bind_signals(self.text_edit, "text_changed", "cursor_changed")
    self.bind_signals(self.scroll_container, "scroll_started", "scroll_ended")
    self.bind_signal(self, ("resized", "_rescale"))
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
    self.rescale()
    self.watch()

  proc enable_selecting() =
    self.text_edit.add_color_override("selection_color", self.selection_color)
    self.text_edit.add_color_override("caret_color", self.caret_color)
    self.scroll_state = Selecting
    self.text_edit.mouse_filter = MOUSE_FILTER_STOP
    self.text_edit.selecting_enabled = true
    if not self.text_edit.is_selection_active:
      self.selection_timer = get_mono_time() + 2.0.seconds
      self.scroll_state = WaitingForSelection

  proc enable_scrolling() =
    self.text_edit.add_color_override("selection_color", clear)
    self.text_edit.add_color_override("caret_color", clear)
    self.scroll_state = Scrolling
    self.text_edit.mouse_filter = MOUSE_FILTER_IGNORE
    self.text_edit.selecting_enabled = false

  proc enable_detecting() =
    self.start_scroll = self.scroll_container.scroll_vertical
    self.text_edit.add_color_override("selection_color", clear)
    self.text_edit.add_color_override("caret_color", clear)
    self.scroll_state = Detecting

  proc enable_idle() =
    self.text_edit.add_color_override("selection_color", self.selection_color)
    self.text_edit.add_color_override("caret_color", self.caret_color)
    self.scroll_state = Idle
    self.text_edit.mouse_filter = MOUSE_FILTER_PASS
    self.text_edit.selecting_enabled = true

  method process(delta: float) =
    if self.adjust_scroll_next_frame:
      self.adjust_scroll_next_frame = false
      self.scroll_to_cursor()

    if self.scroll_state == Detecting:
      if abs(self.scroll_container.scroll_vertical - self.start_scroll) > 20:
        self.enable_scrolling
      elif get_mono_time() > self.touch_timer:
        self.enable_selecting()
    elif self.scroll_state == Selecting and
        not self.text_edit.is_selection_active:
      self.selection_timer = get_mono_time() + 0.5.seconds
      self.scroll_state = WaitingForSelection
    elif self.scroll_state == WaitingForSelection and
        self.text_edit.is_selection_active:
      self.scroll_state = Selecting
    elif self.scroll_state == WaitingForSelection and
        get_mono_time() > self.selection_timer:
      self.enable_idle

  method on_scroll_started() =
    if not self.text_edit.is_selection_active:
      self.enable_detecting
    else:
      self.enable_selecting

  method on_scroll_ended() =
    self.enable_idle

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
