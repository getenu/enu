import pkg/[godot]
import
  godotapi/[
    margin_container, input_event, scene_tree, scene_tree_tween, method_tweener,
    tween, control, text_edit,
  ]
import ui/[markdown_label, editor]
import core, gdutils, models/[states, colors]

proc set_filter(self: Control, filter: int64) =
  self.mouse_filter = filter
  for child in self.get_children:
    let child = child.as_object(Node)
    if child of Control:
      set_filter(Control(child), filter)

gdobj RightPanel of MarginContainer:
  var
    label: MarkdownLabel
    code: TextEdit
      ## A player's code fills the panel in the left editor's TextEdit, not as
      ## a markdown code block.
    zid: EID
    margin = 3.0
    center = 1.0

  method offset_x*(offset: float) {.gdexport.} =
    let width = self.rect_size.x
    self.rect_position =
      vec2(width * offset + self.margin, self.rect_position.y)

  method ready*() =
    self.label = self.find_node("MarkdownLabel") as MarkdownLabel
    self.code =
      self.get_node("../LeftPanel").find_node("Editor").get_node(
        "TextEdit"
      ).duplicate as TextEdit
    self.code.readonly = true
    self.code.always_draw_caret = false
    self.code.visible = false
    self.code.configure_highlighting
    self.add_child(self.code)
    self.move_child(self.code, self.label.get_index + 1)

    state.nodes.game.bind_signal(self.label, "gui_input", self.name)
    state.nodes.game.bind_signal(self.code, "gui_input", self.name)
    self.bind_signal(find("Close", Control), ("pressed", "close"))

    state.status_message_value.changes:
      if added:
        if ?change.item:
          state.push_flags DOCS_VISIBLE, DOCS_FOCUSED
          self.code.visible = false
          self.label.visible = true
          self.label.markdown = change.item
          self.label.update
        else:
          state.pop_flags DOCS_FOCUSED, DOCS_VISIBLE
          self.label.markdown = ""
          self.label.update

    state.player.open_sign_value.changes:
      if added and change.item != nil:
        state.push_flags DOCS_VISIBLE, DOCS_FOCUSED
        var sign = change.item
        self.code.visible = sign.text_only
        self.label.visible = not sign.text_only
        self.show_more(sign, sign.more)
        self.zid = sign.more_value.changes:
          if added:
            self.show_more(sign, change.item)
      if removed and change.item != nil:
        if change.item.more_value.valid:
          change.item.more_value.untrack(self.zid)
      if removed and not ?state.player.open_sign:
        state.pop_flags DOCS_FOCUSED, DOCS_VISIBLE

    state.local_flags.changes:
      if FULL_WIDTH_PANELS.added:
        self.center = 0.0
        self.anchor_left = 0.0
        self.margin_left = 0.0
        self.margin_right = 1.0
      elif FULL_WIDTH_PANELS.removed:
        self.center = 1.0
        self.anchor_left = 0.5
        self.margin_left = 2.0

      if DOCS_VISIBLE.added:
        var tween = self.get_tree.create_tween()
        self.visible = true
        discard tween
          .tween_method(
            self, "_offset_x", 2.0.to_variant, self.center.to_variant,
            animation_duration,
          )
          .set_trans(TRANS_EXPO)
          .set_ease(EASE_IN_OUT)
      elif DOCS_VISIBLE.removed:
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
      elif DOCS_FOCUSED.added:
        self.raisee()
        find("Close", Control).visible = true
      elif DOCS_FOCUSED.removed:
        self.label.release_focus
        self.code.release_focus
        if FULL_WIDTH_PANELS in state.local_flags and
            VIEWPORT_FOCUSED notin state.local_flags:
          find("Close", Control).visible = false
      elif COMMAND_MODE.added:
        self.ghost()
      elif COMMAND_MODE.removed:
        self.unghost()
        find("Overlay", Control).set_mouse_filter_recursive(MOUSE_FILTER_IGNORE)
        find("Close", Control).mouse_filter = MOUSE_FILTER_STOP

  proc show_more(sign: Sign, more: string) =
    if sign.text_only:
      self.code.text = more
    else:
      self.label.markdown = more
      self.label.update

  method on_close() =
    state.player.open_sign = nil

  method unhandled_input*(event: InputEvent) =
    if DOCS_FOCUSED in state.local_flags and event.is_action_pressed("ui_cancel"):
      if not (event of InputEventJoypadButton) or
          COMMAND_MODE notin state.local_flags:
        state.player.open_sign = nil
        self.get_tree().set_input_as_handled()
