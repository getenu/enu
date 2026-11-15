import
  godotapi/[
    h_box_container, control, scene_tree, scene_tree_tween, property_tweener,
    method_tweener, tween, button, image_texture, resource_loader, packed_scene,
    texture,
  ]
import std/[tables]
import pkg/[godot]
import core, models/builds
import gdutils, ui/[preview_maker, action_button]

type PreviewResult = tuple[button: string, preview: Image]

const
  block_buttons = ["blue", "red", "green", "black", "white", "brown"]
    ## The block tools' button names, in DEFAULT_TOOL_COLORS order.
  STACK_GAP = 6.0
  STACK_IDLE_ALPHA = 0.6
    ## How much of the stack shows while its modifier is off.
  CODE_STACK = {
    CODE_MODE: ("code", "code"),
    MOVE_TOOL: ("move", "move_tool"),
    LIFT_TOOL: ("lift", "lift_tool"),
    TURN_TOOL: ("turn", "turn_tool"),
  }.to_table
    ## Each code tool's stack button name and icon.
  STACK_SCALE = 0.6
  STACK_FADE = [1.0, 1.0, 0.4, 0.15]
    ## How much of each code tool shows at rest, by its place in the stack
    ## (0 is the toolbar).
  STACK_AWAKE = 1.5
    ## How long the code stack stays fully shown after it's used.
  STACK_FADE_TIME = 0.5
  STACK_TURN_TIME = 0.25

gdobj Toolbar of HBoxContainer:
  var
    preview_maker: PreviewMaker
    shown_colors: seq[Color]
      ## The color each block button's icon shows (or is being made for).
    blocks: seq[int] ## block buttons waiting for a new icon
    objects = @["bot"]
    preview_result: Option[PreviewResult]
    waiting = false
    zid: EID
    tween: SceneTreeTween
    stack: Button
      ## The selected block tool's stack: one "+" that turns on create mode.
    code_buttons: Table[Tools, Button]
      ## A button for each code tool, for the stack above the code button.
      ## The one in the toolbar shows only while it's moving.
    shown_code: seq[Tools] ## The code tools in the order they're shown.
    turned_from: seq[Tools] ## Their order before the stack last turned.
    turning = 1.0 ## How far the stack has turned, from 0 to 1.
    awake = 0.0 ## How much longer the code stack stays fully shown.

  method ready*() =
    self.bind_signals self, "action_changed"
    self.preview_maker = self.get_node("../PreviewMaker") as PreviewMaker
    assert not self.preview_maker.is_nil
    self.stack = self.get_node("Button-new") as Button
    # floats above the selected tool instead of taking a place in the row
    self.stack.set_as_toplevel(true)
    let button_scene = load("res://components/ActionButton.tscn") as PackedScene
    for tool, (name, icon) in CODE_STACK:
      let button = button_scene.instance() as Button
      button.name = "Button-stack-" & name
      button.icon = load("res://textures/" & icon & ".png") as Texture
      button.toggle_mode = false
      ActionButton(button).size_scale = STACK_SCALE
      self.add_child(button)
      button.set_as_toplevel(true)
      button.visible = false
      self.code_buttons[tool] = button
    self.shown_code = code_tools()
    self.turned_from = self.shown_code
    self.code_button.icon = self.code_buttons[self.shown_code[0]].icon

    state.local_flags.changes:
      if CREATE_MODE.added:
        self.stack.set_pressed true
      elif CREATE_MODE.removed:
        self.stack.set_pressed false

    let player = state.player
    player.flags.changes:
      if PLAYING.added:
        self.visible = false
        player.tool = DISABLED
      if PLAYING.removed:
        self.visible = true
        player.tool = if BLUE_BLOCK in player.tools: BLUE_BLOCK else: NONE

    self.zid = state.player.tool_value.changes:
      if added:
        self.show_pressed change.item

    self.update_block_icons()
    state.player.tool_colors.changes:
      self.update_block_icons()

    self.apply_visibility()
    state.player.tools.changes:
      # Level load seeds the tool set before the scene is interactive — snap to
      # it instead of sliding, so a customized level doesn't open with a switch.
      if LOADING_LEVEL in state.global_flags:
        self.apply_tools()
      else:
        self.animate_tools()

  proc update_block_icons() =
    let colors = state.player.tool_colors.value
    self.shown_colors.set_len(colors.len)
    for i, color in colors:
      if color != self.shown_colors[i]:
        self.shown_colors[i] = color
        if i notin self.blocks:
          self.blocks.add i

  proc apply_visibility() =
    for tool in CODE_MODE .. PLACE_BOT:
      let b = self.get_child(int tool) as Button
      if ?b:
        b.visible = tool in state.player.tools

  proc code_button(): Button =
    self.get_child(int CODE_MODE) as Button

  proc show_pressed(tool: Tools) =
    if tool.slot in {CODE_MODE .. PLACE_BOT}:
      let b = self.get_child(int tool.slot) as Button
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
    self.show_pressed state.player.tool

  proc animate_tools() =
    # Slide the toolbar down and back up, swapping in the updated tool set at the
    # bottom — matching the Settings slide-up look (vertical only).
    #
    # Animate margin_bottom, never rect_position: writing the position of an
    # anchored control rewrites both margins to pin its current rect, freezing
    # the container at that height — after which a smaller toolbar_size can only
    # shrink the buttons' width. Moving the bottom margin keeps the height
    # anchor-driven, and the rest state is just the scene's 5px bottom margin.
    if ?self.tween:
      self.tween.kill
    self.margin_bottom = -5.0

    let drop = self.rect_size.y + 10.0
    self.tween = self.get_tree.create_tween()
    discard self.tween
      .tween_property(
        self, "margin_bottom", (drop - 5.0).to_variant, animation_duration
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)
    discard self.tween.tween_callback(self, "_apply_tools")
    discard self.tween
      .tween_property(
        self, "margin_bottom", (-5.0).to_variant, animation_duration
      )
      .set_trans(TRANS_EXPO)
      .set_ease(EASE_IN_OUT)

  proc place_stack() =
    let tool = state.player.tool
    let button =
      if tool in BLOCK_TOOLS:
        self.get_child(int tool) as Button
      else:
        nil
    self.stack.visible = self.visible and ?button and button.visible
    if self.stack.visible:
      let size = self.stack.rect_size
      self.stack.rect_global_position =
        button.rect_global_position +
        vec2((button.rect_size.x - size.x) / 2, -size.y - STACK_GAP)
      self.stack.modulate =
        if CREATE_MODE in state.local_flags:
          init_color(1.0, 1.0, 1.0, 1.0)
        else:
          init_color(1.0, 1.0, 1.0, STACK_IDLE_ALPHA)

  proc code_stack_place(button: Button, height: int): (Vector2, float) =
    ## Where `button` goes `height` places up the code stack, and its scale.
    let slot = self.code_button
    let size = button.rect_size
    if height == 0:
      (slot.rect_global_position, slot.rect_size.x / size.x)
    else:
      let x = (slot.rect_size.x - size.x) / 2
      let y = -height.float * (size.y + STACK_GAP)
      (slot.rect_global_position + vec2(x, y), 1.0)

  proc place_code_stack(delta: float) =
    let tools = code_tools()
    if tools != self.shown_code:
      self.turned_from = self.shown_code
      self.shown_code = tools
      self.turning = 0.0
      self.awake = STACK_AWAKE
      self.code_button.icon = nil
    if self.turning < 1.0:
      self.turning = min(1.0, self.turning + delta / STACK_TURN_TIME)
      if self.turning == 1.0:
        self.code_button.icon = self.code_buttons[tools[0]].icon

    let shown =
      self.visible and self.code_button.visible and
      state.player.tool in CODE_TOOLS
    if shown and MOUSE_CAPTURED notin state.local_flags:
      let mouse = self.get_global_mouse_position()
      for button in self.code_buttons.values:
        let rect = button.get_global_rect
        if button.visible and mouse.x >= rect.position.x and
            mouse.y >= rect.position.y and
            mouse.x < rect.position.x + rect.size.x and
            mouse.y < rect.position.y + rect.size.y:
          self.awake = max(self.awake, STACK_FADE_TIME)
    self.awake = max(0.0, self.awake - delta)
    let
      wake = min(1.0, self.awake / STACK_FADE_TIME)
      t = self.turning
      eased = t * t * (3 - 2 * t)
    for tool, button in self.code_buttons:
      let
        to = tools.find(tool)
        start = self.turned_from.find(tool)
      button.visible = shown and (to != 0 or eased < 1.0)
      if button.visible:
        let
          (from_pos, from_scale) = self.code_stack_place(button, start)
          (to_pos, to_scale) = self.code_stack_place(button, to)
          scale = from_scale + (to_scale - from_scale) * eased
          rest = STACK_FADE[start] + (STACK_FADE[to] - STACK_FADE[start]) * eased
          alpha = rest + (1.0 - rest) * wake
        button.rect_global_position = from_pos + (to_pos - from_pos) * eased
        button.rect_scale = vec2(scale, scale)
        button.modulate = init_color(1.0, 1.0, 1.0, alpha)

  method process*(delta: float) =
    self.place_stack()
    self.place_code_stack(delta)
    if self.preview_result.is_some:
      let
        p = self.preview_result.get
        b = self.get_node("Button-" & p.button) as Button
      self.preview_result = none(PreviewResult)
      var tex = gdnew[ImageTexture]()
      tex.create_from_image(p.preview)
      b.icon = tex

    if not self.waiting and self.blocks.len > 0:
      let index = self.blocks.pop()
      self.waiting = true
      self.preview_maker.generate_block_preview self.shown_colors[index],
        proc(preview: Image) =
          self.preview_result = some (button: block_buttons[index], preview: preview)
          self.waiting = false
    if not self.waiting and self.blocks.len == 0 and self.objects.len > 0:
      let obj = self.objects.pop()
      self.waiting = true
      self.preview_maker.generate_object_preview obj,
        proc(preview: Image) =
          self.preview_result = some (button: obj, preview: preview)
          self.waiting = false

  method on_action_changed*(button_name: string) =
    for tool, (name, _) in CODE_STACK:
      if button_name == "Button-stack-" & name:
        self.awake = STACK_AWAKE
        state.player.select_tool tool
        return
    state.player.tool_value.pause(self.zid):
      case button_name[7 ..^ 1]
      of "code":
        state.select_or_modify CODE_MODE
      of "blue":
        state.select_or_modify BLUE_BLOCK
      of "red":
        state.select_or_modify RED_BLOCK
      of "green":
        state.select_or_modify GREEN_BLOCK
      of "black":
        state.select_or_modify BLACK_BLOCK
      of "white":
        state.select_or_modify WHITE_BLOCK
      of "brown":
        state.select_or_modify BROWN_BLOCK
      of "bot":
        state.player.tool = PLACE_BOT
      of "new":
        state.toggle_create_mode
