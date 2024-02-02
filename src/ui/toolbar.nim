import godotapi/[h_box_container, scene_tree, button, image_texture]
import pkg/[godot]
import core
import globals, ui/preview_maker

type PreviewResult = tuple[color: string, preview: Image]

gdobj Toolbar of HBoxContainer:
  var
    preview_maker: PreviewMaker
    blocks = @["green", "red", "blue", "black", "white", "brown"]
    objects = @["bot"]
    preview_result: Option[PreviewResult]
    waiting = false
    zid: ZID

  method ready*() =
    self.bind_signals self, "action_changed"
    self.preview_maker = self.get_node("../PreviewMaker") as PreviewMaker
    assert not self.preview_maker.is_nil

    state.local_flags.changes:
      if Playing.added:
        self.visible = false
        state.tool = Disabled
      if Playing.removed:
        self.visible = true
        state.tool = BlueBlock

    self.zid =
      state.tool_value.changes:
        if added:
          let b = self.get_child(int(change.item)) as Button
          if ?b:
            b.set_pressed true

  method process*(delta: float) =
    if self.preview_result.is_some:
      let
        p = self.preview_result.get
        b = self.get_node("Button-" & p.color) as Button
      self.preview_result = none(PreviewResult)
      var tex = gdnew[ImageTexture]()
      tex.create_from_image(p.preview)
      b.icon = tex

    if not self.waiting and self.blocks.len > 0:
      var color = self.blocks.pop()
      self.waiting = true
      self.preview_maker.generate_block_preview \"{color}-block-grid",
        proc(preview: Image) =
          self.preview_result = some (color: color, preview: preview)
          self.waiting = false
    if not self.waiting and self.blocks.len == 0 and self.objects.len > 0:
      let obj = self.objects.pop()
      self.waiting = true
      self.preview_maker.generate_object_preview obj,
        proc(preview: Image) =
          self.preview_result = some (color: obj, preview: preview)

  method on_action_changed*(button_name: string) =
    state.tool_value.pause(self.zid):
      case button_name[7 ..^ 1]
      of "code":
        state.tool = CodeMode
      of "blue":
        state.tool = BlueBlock
      of "red":
        state.tool = RedBlock
      of "green":
        state.tool = GreenBlock
      of "black":
        state.tool = BlackBlock
      of "white":
        state.tool = WhiteBlock
      of "brown":
        state.tool = BrownBlock
      of "bot":
        state.tool = PlaceBot
