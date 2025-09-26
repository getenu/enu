import std/[options, strutils, sequtils]
import gdext
# Use custom Godot bindings for consistency with other classes
import
  gdext/classes/[gdhboxcontainer, gdbutton, gdnode, gdimagetexture, gdimage]
import core, gdcore
import ui/preview_maker

# Note: Tool state is now managed through the global state.current_tool
# Using the global Tools enum from types.nim instead of local ToolType

type PreviewResult = object
  color: string
  preview: gdref Image

type Toolbar* {.gdsync.} =
  ptr object of HBoxContainer
    preview_maker: PreviewMaker
    blocks: seq[string]
    objects: seq[string]
    preview_result: Option[PreviewResult]
    waiting: bool

# Forward declarations
proc set_tool(self: Toolbar, tool: Tools)
proc update_button_states(self: Toolbar, tool: Tools)

method onInit*(self: Toolbar) =
  # Constructor-like initialization
  discard

method ready*(self: Toolbar) {.gdsync.} =
  print("[UI] Toolbar ready")

  # Connect to action_changed signals from ActionButton components
  if not self.has_signal("action_changed"):
    self.add_user_signal("action_changed")
  let callable_obj = callable(self, new_string_name("_on_action_changed"))
  discard self.connect(new_string_name("action_changed"), callable_obj)

  # Find the PreviewMaker node (it's inside a SubViewport)
  self.preview_maker =
    self.get_node("../PreviewMaker/PreviewWorld").as(PreviewMaker)
  if not ?self.preview_maker:
    print(
      "[UI] ✗ PreviewMaker not found - toolbar preview generation will be disabled"
    )
  else:
    print("[UI] ✓ PreviewMaker found for toolbar preview generation")

  # Initialize tool lists for preview generation
  self.blocks = @["green", "red", "blue", "black", "white", "brown"]
  self.objects = @["bot"]
  self.waiting = false
  self.preview_result = none(PreviewResult)

  # TODO: Connect to game state changes
  # state.local_flags.changes:
  #   if Playing.added:
  #     self.visible = false
  #   if Playing.removed:
  #     self.visible = true

  # Watch for tool changes to update button states (like keyboard shortcuts)
  state.current_tool_value.changes:
    if added:
      self.update_button_states(change.item)

  # Set initial tool selection
  self.set_tool(BlueBlock)

  print("[UI] Toolbar initialized with " & $self.get_child_count() & " buttons")

proc handle_tool_selection(self: Toolbar, button_name: string) =
  print("[UI] Toolbar handling tool selection: " & button_name)

  if button_name.len > 7 and button_name.startsWith("Button-"):
    let tool_name = button_name[7 ..^ 1] # Skip "Button-" prefix

    let new_tool =
      case tool_name
      of "code": CodeMode
      of "blue": BlueBlock
      of "red": RedBlock
      of "green": GreenBlock
      of "black": BlackBlock
      of "white": WhiteBlock
      of "brown": BrownBlock
      of "bot": PlaceBot
      else: BlueBlock
      # Default fallback

    # Update the current tool in global state
    state.current_tool = new_tool
    print("[UI] Tool changed to: " & $new_tool)

proc on_action_changed*(self: Toolbar, button_name: string) {.gdsync, name: "_on_action_changed".} =
  print("[UI] Toolbar action_changed signal received: " & button_name)
  self.handle_tool_selection(button_name)

method process*(self: Toolbar, delta: float64) {.gdsync.} =
  # Handle preview result and update button icons
  if self.preview_result.is_some:
    let p = self.preview_result.get()
    let button_node = self.get_node("Button-" & p.color)
    if ?button_node:
      let button = button_node.as(Button)
      if ?button:
        # Create ImageTexture from the preview image with mipmaps for better quality
        let preview_img = p.preview
        # discard preview_img[].generateMipmaps()
        let tex = ImageTexture.create_from_image(preview_img)
        button.set_button_icon(tex.as(gdref Texture2D))
        print("[UI] ✓ Set preview icon for button: Button-", p.color)
      else:
        print("[UI] ✗ Failed to cast node to Button: Button-", p.color)
    else:
      print("[UI] ✗ Button not found: Button-", p.color)
    self.preview_result = none(PreviewResult)

  # Generate previews for remaining blocks
  if not self.waiting and self.blocks.len > 0 and ?self.preview_maker:
    let color = self.blocks.pop()
    self.waiting = true
    print("[UI] Generating preview for block: ", color)

    self.preview_maker.generate_block_preview(
      color & "-block-grid",
      proc(preview: gdref Image) {.gcsafe.} =
        if ?preview:
          self.preview_result =
            some(PreviewResult(color: color, preview: preview))
          print("[UI] ✓ Preview generated for: ", color)
        else:
          print("[UI] ✗ Preview generation failed for: ", color)
        self.waiting = false,
    )

  # Generate previews for remaining objects
  if not self.waiting and self.blocks.len == 0 and self.objects.len > 0 and
      ?self.preview_maker:
    let obj = self.objects.pop()
    self.waiting = true
    print("[UI] Generating preview for object: ", obj)

    self.preview_maker.generate_object_preview(
      obj,
      proc(preview: gdref Image) {.gcsafe.} =
        if ?preview:
          self.preview_result =
            some(PreviewResult(color: obj, preview: preview))
          print("[UI] ✓ Preview generated for object: ", obj)
        else:
          print("[UI] ✗ Preview generation failed for object: ", obj)
        self.waiting = false,
    )

proc update_button_states(self: Toolbar, tool: Tools) =
  ## Update all button pressed states to match the current tool
  let tool_name =
    case tool
    of CodeMode: "code"
    of BlueBlock: "blue"
    of RedBlock: "red"
    of GreenBlock: "green"
    of BlackBlock: "black"
    of WhiteBlock: "white"
    of BrownBlock: "brown"
    of PlaceBot: "bot"
    of Disabled: ""

  # Unpress all buttons first
  for i in 0..<self.get_child_count():
    let child = self.get_child(i.int32)
    if ?child:
      let button = child.as(Button)
      if ?button:
        button.set_pressed(false)

  # Press the active tool button
  if tool_name.len > 0:
    let button_name = "Button-" & tool_name
    let button_node = self.get_node(NodePath(button_name))
    if ?button_node:
      let button = button_node.as(Button)
      if ?button:
        button.set_pressed(true)
        print("[TOOLBAR] Button state updated to: " & tool_name)

proc set_tool(self: Toolbar, tool: Tools) =
  ## Set the current tool and update button states
  state.current_tool = tool

  # Update button visual states
  self.update_button_states(tool)

# Proc to be called by ActionButtons when they're pressed
proc handle_button_press(self: Toolbar, button_name: string) =
  self.on_action_changed(button_name)
