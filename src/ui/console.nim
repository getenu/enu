import
  godotapi/[
    text_edit, scene_tree, node, input_event, input_event_key, rich_text_label,
    global_constants
  ]
import godot
import std/strutils
import core, globals

gdobj Console of RichTextLabel:
  var default_mouse_filter: int64

  proc init*() =
    state.local_flags.changes:
      self.visible = ConsoleVisible in state.local_flags

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
