import godotapi/[h_box_container, scene_tree, button, image_texture]
import pkg/[godot]
import core
import gdutils, ui/preview_maker

type PreviewResult = tuple[color: string, preview: Image]

gdobj Toolbar of HBoxContainer:
  var
    preview_maker: PreviewMaker
    blocks = @["green", "red", "blue", "black", "white", "brown"]
    objects = @["bot"]
    preview_result: Option[PreviewResult]
    waiting = false
    zid: EID

  method ready*() =
    self.bind_signals self, "action_changed"
    self.preview_maker = self.get_node("../PreviewMaker") as PreviewMaker
    assert not self.preview_maker.is_nil

    state.local_flags.changes:
      if PLAYING.added:
        self.visible = false
        state.tool = DISABLED
      if PLAYING.removed:
        self.visible = true
        state.tool = BLUE_BLOCK

    self.zid = state.tool_value.changes:
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
        state.tool = CODE_MODE
      of "blue":
        state.tool = BLUE_BLOCK
      of "red":
        state.tool = RED_BLOCK
      of "green":
        state.tool = GREEN_BLOCK
      of "black":
        state.tool = BLACK_BLOCK
      of "white":
        state.tool = WHITE_BLOCK
      of "brown":
        state.tool = BROWN_BLOCK
      of "bot":
        state.tool = PLACE_BOT
