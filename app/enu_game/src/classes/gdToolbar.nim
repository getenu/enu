import std/[options, strutils, sequtils]
import gdext
# Use custom Godot bindings for consistency with other classes
import gdext/classes/[gdhboxcontainer, gdbutton, gdnode]

# Tool types - simplified version of original game tools
type ToolType* = enum
  Disabled
  CodeMode
  BlueBlock
  RedBlock  
  GreenBlock
  BlackBlock
  WhiteBlock
  BrownBlock
  PlaceBot

# Simple state management - will eventually connect to full game state
var current_tool* = BlueBlock

type Toolbar* {.gdsync.} = ptr object of HBoxContainer
  blocks: seq[string]
  objects: seq[string]
  waiting: bool

method onInit*(self: Toolbar) =
  # Constructor-like initialization
  discard

method ready*(self: Toolbar) {.gdsync.} =
  print("[UI] Toolbar ready")
  
  # Initialize tool lists for preview generation (simplified for now)
  self.blocks = @["green", "red", "blue", "black", "white", "brown"] 
  self.objects = @["bot"]
  self.waiting = false
  
  # TODO: Connect to game state changes
  # state.local_flags.changes:
  #   if Playing.added:
  #     self.visible = false
  #   if Playing.removed:
  #     self.visible = true
  
  # Set initial tool selection
  # TODO: Fix set_tool call - temporarily commented out for build
  # self.set_tool(BlueBlock)
  current_tool = BlueBlock
  
  print("[UI] Toolbar initialized with " & $self.getChildCount() & " buttons")

method process*(self: Toolbar; delta: float) {.gdsync.} =
  # Handle preview generation and other toolbar updates
  # This is simplified - the original had complex preview generation
  
  # TODO: Implement preview generation when we have the PreviewMaker
  # if self.preview_result.is_some:
  #   let p = self.preview_result.get
  #   let b = self.get_node("Button-" & p.color) as Button
  #   # Update button icon with generated preview
  discard # Placeholder until preview generation is implemented

proc set_tool*(self: Toolbar, tool: ToolType) {.gdsync.} =
  ## Set the current tool and update button states
  current_tool = tool
  
  # Find and press the corresponding button
  let tool_name = case tool
    of CodeMode: "code"
    of BlueBlock: "blue" 
    of RedBlock: "red"
    of GreenBlock: "green"
    of BlackBlock: "black"
    of WhiteBlock: "white"
    of BrownBlock: "brown"
    of PlaceBot: "bot"
    of Disabled: ""
  
  if tool_name.len > 0:
    let button_name = "Button-" & tool_name
    let button_node = self.getNode(NodePath(button_name))
    if not button_node.is_nil():
      let button = button_node as Button
      if not button.is_nil():
        button.setPressed(true)
        print("[TOOLBAR] Tool set to: " & tool_name)

proc on_action_changed*(self: Toolbar, button_name: string) {.gdsync.} =
  ## Handle tool change from ActionButton
  print("[TOOLBAR] Action changed: " & button_name)
  
  if button_name.len > 7 and button_name.startsWith("Button-"):
    let tool_name = button_name[7..^1] # Skip "Button-" prefix
    
    let new_tool = case tool_name
      of "code": CodeMode
      of "blue": BlueBlock
      of "red": RedBlock
      of "green": GreenBlock
      of "black": BlackBlock
      of "white": WhiteBlock
      of "brown": BrownBlock
      of "bot": PlaceBot
      else: Disabled
    
    if new_tool != Disabled:
      # TODO: Fix set_tool architecture later
      current_tool = new_tool
      print("[TOOLBAR] Tool changed to: " & $new_tool)

# Proc to be called by ActionButtons when they're pressed
proc handle_button_press*(self: Toolbar, button_name: string) {.gdsync.} =
  self.on_action_changed(button_name)