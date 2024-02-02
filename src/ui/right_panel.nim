import pkg/[godot]
import godotapi/[margin_container, input_event, scene_tree]
import ui/markdown_label
import core, models/[states, colors]

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
  var label: MarkdownLabel
  var zid: ZID

  method ready*() =
    self.label = self.find_node("MarkdownLabel") as MarkdownLabel

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
        self.zid =
          sign.more_value.changes:
            if added:
              self.label.markdown = md(sign, change.item)
              self.label.update
      if removed and change.item != nil:
        if change.item.more_value.valid:
          change.item.more_value.untrack(self.zid)
        state.pop_flags DocsFocused, DocsVisible

    state.local_flags.changes:
      if DocsVisible.added:
        self.label.visible = true
      elif DocsVisible.removed:
        self.label.visible = false
      elif DocsFocused.removed:
        self.label.release_focus
      elif CommandMode.added:
        self.modulate = dimmed_alpha
      elif CommandMode.removed:
        self.modulate = solid_alpha

  method unhandled_input*(event: InputEvent) =
    if DocsFocused in state.local_flags and event.is_action_pressed("ui_cancel"):
      if not (event of InputEventJoypadButton) or
          CommandMode notin state.local_flags:
        state.open_sign = nil
        self.get_tree().set_input_as_handled()
