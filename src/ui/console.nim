import
  godotapi/[
    text_edit, scene_tree, node, input_event, input_event_key, rich_text_label,
    global_constants, scene_tree_tween, tween, property_tweener, method_tweener
  ]
import godot
import std/strutils
import core, gdutils

gdobj Console of RichTextLabel:
  var
    default_mouse_filter: int64
    tween: SceneTreeTween

  method offset_x*(offset: float) {.gdexport.} =
    let width = self.rect_size.x
    self.rect_position = vec2(width * offset, self.rect_position.y)

  proc show() =
    self.opacity = 1.0
    if ?self.tween:
      self.tween.kill
    self.tween = self.get_tree.create_tween
    self.visible = true
    discard
      self.tween
      .tween_method(
        self, "_offset_x", -1.0.to_variant, 0.0.to_variant, animation_duration
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)

  proc hide() =
    if ?self.tween:
      self.tween.kill
    self.tween = self.get_tree.create_tween
    self.rect_position = vec2(0.0, self.rect_position.y)
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

  proc init*() =
    state.local_flags.changes:
      if ConsoleVisible.added:
        self.show()
      elif ConsoleVisible.removed:
        self.hide()
      elif CommandMode.added:
        self.ghost()
      elif CommandMode.removed:
        self.unghost()
    state.console.log.changes:
      if added:
        discard self.append_bbcode(change.item)
      elif removed:
        self.clear()
        discard self.append_bbcode(state.console.log.value.join("\n"))
        break

    self.default_mouse_filter = self.mouse_filter

  method ready*() =
    state.local_flags.changes:
      if MouseCaptured.added:
        self.mouse_filter = MOUSE_FILTER_IGNORE
      elif MouseCaptured.removed:
        self.mouse_filter = self.default_mouse_filter

    state.nodes.game.bind_signals(self, "meta_clicked")
    state.nodes.game.bind_signal(self, "gui_input", self.name)

    if ConsoleVisible notin state.local_flags:
      self.opacity = 0.0
      self.hide()

    for child in self.get_children():
      let o = child.as_object(Node) as VScrollBar
      if ?o:
        o.modulate = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.0)

    self.bind_signal(find("Close", Control), ("pressed", "close"))

  method on_close() =
    state.pop_flags ConsoleVisible, ConsoleFocused

  method unhandled_input*(event: InputEvent) =
    if ConsoleFocused in state.local_flags and
        event.is_action_pressed("ui_cancel"):
      if not (event of InputEventJoypadButton) or
          CommandMode notin state.local_flags:
        state.pop_flags ConsoleVisible, ConsoleFocused
        self.get_tree().set_input_as_handled()
