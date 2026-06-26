import
  godotapi/[
    h_box_container, scene_tree, scene_tree_tween, property_tweener,
    method_tweener, tween, button, image_texture,
  ]
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
    tween: SceneTreeTween
    rest_y: float
    rest_y_set: bool

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
        state.tool = if BLUE_BLOCK in state.tools: BLUE_BLOCK else: NONE

    self.zid = state.tool_value.changes:
      if added:
        self.show_pressed change.item

    self.apply_visibility()
    state.tools.changes:
      self.animate_tools()

  proc apply_visibility() =
    for tool in CODE_MODE .. PLACE_BOT:
      let b = self.get_child(int tool) as Button
      if ?b:
        b.visible = tool in state.tools

  proc show_pressed(tool: Tools) =
    if tool in {CODE_MODE .. PLACE_BOT}:
      let b = self.get_child(int tool) as Button
      if ?b:
        b.set_pressed true
    else:
      # NONE / DISABLED: clear the selection so nothing looks active.
      for t in CODE_MODE .. PLACE_BOT:
        let b = self.get_child(int t) as Button
        if ?b:
          b.set_pressed false

  method apply_tools*() {.gdexport.} =
    # Runs at the bottom of the slide, while the toolbar is off-screen, so the
    # button set changes out of sight.
    self.apply_visibility()
    self.show_pressed state.tool

  proc animate_tools() =
    # Slide the toolbar down and back up, swapping in the updated tool set at the
    # bottom — matching the Settings slide-up look (vertical only).
    if not self.rest_y_set:
      self.rest_y = self.rect_position.y
      self.rest_y_set = true
    if ?self.tween:
      self.tween.kill
    self.rect_position = vec2(self.rect_position.x, self.rest_y)

    let drop = self.rect_size.y + 10.0
    self.tween = self.get_tree.create_tween()
    discard self.tween
      .tween_property(
        self, "rect_position:y", (self.rest_y + drop).to_variant,
        animation_duration,
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)
    discard self.tween.tween_callback(self, "_apply_tools")
    discard self.tween
      .tween_property(
        self, "rect_position:y", self.rest_y.to_variant, animation_duration
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)

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
          self.waiting = false

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
