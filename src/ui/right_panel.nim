import pkg/[godot]
import
  godotapi/[
    margin_container, input_event, scene_tree, scene_tree_tween, method_tweener,
    tween, control,
  ]
import ui/markdown_label
import core, gdutils, models/[states, colors]

proc set_filter(self: Control, filter: int64) =
  self.mouse_filter = filter
  for child in self.get_children:
    let child = child.as_object(Node)
    if child of Control:
      set_filter(Control(child), filter)

proc md(self: Sign, md: string): string =
  if self.text_only:
    "```nim\n" & md & "\n```"
  else:
    md

gdobj RightPanel of MarginContainer:
  var
    label: MarkdownLabel
    zid: ZID
    margin = 3.0
    center = 1.0

  method offset_x*(offset: float) {.gdexport.} =
    let width = self.rect_size.x
    self.rect_position =
      vec2(width * offset + self.margin, self.rect_position.y)

  method ready*() =
    self.label = self.find_node("MarkdownLabel") as MarkdownLabel

    state.nodes.game.bind_signal(self.label, "gui_input", self.name)
    self.bind_signal(find("Close", Control), ("pressed", "close"))

    state.status_message_value.changes:
      if added:
        if ?change.item:
          state.push_flags DocsVisible, DocsFocused
          self.label.markdown = change.item
          self.label.update
        else:
          state.pop_flags DocsFocused, DocsVisible
          self.label.markdown = ""
          self.label.update

    state.open_sign_value.changes:
      if added and change.item != nil:
        state.push_flags DocsVisible, DocsFocused
        var sign = change.item
        self.label.markdown = md(sign, sign.more)
        self.label.update
        self.zid = sign.more_value.changes:
          if added:
            self.label.markdown = md(sign, change.item)
            self.label.update
      if removed and change.item != nil:
        if change.item.more_value.valid:
          change.item.more_value.untrack(self.zid)
      if removed and not ?state.open_sign:
        state.pop_flags DocsFocused, DocsVisible

    state.local_flags.changes:
      if FullWidthPanels.added:
        self.margin = 63.0
        self.center = 0.0
        self.anchor_left = 0.0
        self.margin_left = 63.0
        self.margin_right = 1.0
      elif FullWidthPanels.removed:
        self.margin = 3.0
        self.center = 1.0
        self.anchor_left = 0.5
        self.margin_left = 2.0
        self.margin_right = 1.0

      if DocsVisible.added:
        var tween = self.get_tree.create_tween()
        self.visible = true
        discard tween
          .tween_method(
            self, "_offset_x", 2.0.to_variant, self.center.to_variant,
            animation_duration,
          )
          .set_trans(TRANS_EXPO)
          .set_ease(EASE_IN_OUT)
      elif DocsVisible.removed:
        var tween = self.get_tree.create_tween()
        discard tween
          .tween_method(
            self, "_offset_x", self.center.to_variant, 2.0.to_variant,
            animation_duration,
          )
          .set_trans(TRANS_EXPO)
          .set_ease(EASE_IN_OUT)
        discard
          tween.tween_callback(self, "set_visible", new_array(false.to_variant))
      elif DocsFocused.added:
        self.raisee()
        find("Close", Control).visible = true
      elif DocsFocused.removed:
        self.label.release_focus
        if FullWidthPanels in state.local_flags and
            ViewportFocused notin state.local_flags:
          find("Close", Control).visible = false
      elif CommandMode.added:
        self.ghost()
      elif CommandMode.removed:
        self.unghost()
        find("Overlay", Control).set_mouse_filter_recursive(MOUSE_FILTER_IGNORE)
        find("Close", Control).mouse_filter = MOUSE_FILTER_STOP

  method on_close() =
    state.open_sign = nil

  method unhandled_input*(event: InputEvent) =
    if DocsFocused in state.local_flags and event.is_action_pressed("ui_cancel"):
      if not (event of InputEventJoypadButton) or
          CommandMode notin state.local_flags:
        state.open_sign = nil
        self.get_tree().set_input_as_handled()
