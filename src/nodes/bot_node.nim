# MIGRATION STATUS: 80% Complete - Bot entity framework functional, model integration disabled
#
# ✅ FUNCTIONAL:
#   - Bot node initialization and ready() lifecycle
#   - Material management (update, highlight, default setting)
#   - Animation framework (set_walk_animation with placeholder logic)
#   - Visibility management with god mode support
#   - Physics processing for CharacterBody3D movement
#   - Node hierarchy setup (skin, mesh, animation_player)
#   - Resource loading and scene instantiation
#
# 🚧 PARTIALLY FUNCTIONAL (gdext API limitations):
#   - Material validation: gdref Material nil checking disabled - needs gdext validation API
#   - Animation control: AnimationPlayer method calls disabled - needs gdext AnimationPlayer API
#   - Transform updates: Node positioning/transform disabled - needs gdext Node3D API
#   - Model integration: Full model system integration disabled - needs model_citizen API
#
# 🔧 KEY CHANGES FROM GODOT 3:
#   - 184 lines -> 168 lines: Core functionality preserved with gdext adaptations
#   - KinematicBody -> CharacterBody3D: Updated for Godot 4 physics
#   - gdobj BotNode -> type BotNode* {.gdsync.} = ptr object of CharacterBody3D
#   - process() -> physics_process(): Updated for Godot 4 CharacterBody3D lifecycle
#   - Material types changed to gdref Material for gdext compatibility
#   - All model change tracking converted to placeholder/TODO implementations
#
# ❌ DISABLED:
#   - Full model change watching (glow, visibility, scale, color, etc.)
#   - Animation playback control (idle, walk, run, custom animations)
#   - Move and slide physics integration
#   - Transform synchronization with model system
#   - Sight query system integration
#
# 📝 TODOS: Restore model integration, animation control, physics movement, transform sync

import std/[tables, math]
import gdext
import
  gdext/classes/[
    gdcharacterbody3d, gdpackedscene, gdresourceloader, gdnode3d,
    gdmeshinstance3d, gdmaterial, gdanimationplayer, gdstandardmaterial3d,
    gdtextedit, gdraycast3d, gdanimationtree,
  ]
import core, gdcore, models/colors, ui/markdown_label
import queries

type BotNode* {.gdsync.} =
  ptr object of CharacterBody3D
    model*: Unit
    material* {.gdexport.}: gdref Material
    highlight_material* {.gdexport.}: gdref Material
    selected_material* {.gdexport.}: gdref Material
    skin: Node3D
    mesh: MeshInstance3D
    animation_player: AnimationPlayer
    transform_zid: ZID

proc update_material*(self: BotNode, value: gdref Material) =
  assert ?self.mesh, "BotNode mesh must be available"
  assert ?value, "Material must be provided"
  self.mesh.set_surface_override_material(0, value)

proc set_default_material(self: BotNode) =
  self.update_material(self.material)

proc highlight(self: BotNode) =
  self.update_material(self.highlight_material)

method ready*(self: BotNode) {.gdsync.} =
  # Find child nodes
  self.skin = self.find_child("model", false, false).as(Node3D)
  assert ?self.skin, "BotNode must have a 'model' child node"

  # In Godot 4, the mesh is under root/Skeleton3D/body_001 path (note underscore)
  let root_node = self.skin.find_child("root", false, false)
  if ?root_node:
    let skeleton = root_node.find_child("Skeleton3D", false, false)
    if ?skeleton:
      self.mesh = skeleton.find_child("body_001", false, false).as(MeshInstance3D)

  if not ?self.mesh:
    # Fallback: try to find body_001 directly with deep search
    self.mesh = self.skin.find_child("body_001", true, false).as(MeshInstance3D)

  assert ?self.mesh, "BotNode must have a mesh (body_001)"

  self.animation_player =
    self.skin.find_child("AnimationPlayer", false, false).as(AnimationPlayer)
  assert ?self.animation_player, "BotNode must have an AnimationPlayer"

  # Set up material
  if ?self.material:
    self.set_default_material()
  else:
    # Get existing material from mesh as fallback
    let existing_material = self.mesh.get_surface_override_material(0)
    if ?existing_material:
      self.material = existing_material.as(gdref Material)

  # Adjust player model position
  if ?self.model and self.model of Player:
    # hack so player model doesn't hover
    let current_pos = self.skin.get_position()
    self.skin.set_position(current_pos + vector3(0, -0.8, 0))

proc set_color(self: BotNode, color: chroma.Color) =
  assert ?self.material, "BotNode material must be available for color setting"

  var adjusted: chroma.Color

  # Apply color adjustments based on specific colors (matching Godot 3 logic)
  if color == action_colors[Colors.Green]:
    adjusted = color
    adjusted.a = 0.015
  elif color == action_colors[Colors.White]:
    adjusted = color
    adjusted.a = 0.1
  else:
    # Calculate distance-based adjustments for other colors
    var dist = (color.distance(action_colors[Colors.Brown]) + 10).cbrt / 7.5
    adjusted = color.saturate(0.2).darken(dist - 0.15)
    adjusted.a = 0.95 - color.distance(action_colors[Colors.Black]) / 100

  # Convert to Godot Color and directly modify the material (like Godot 3)
  let godot_color = gdext.color(adjusted.r, adjusted.g, adjusted.b, adjusted.a)
  let material = self.material.as(gdref StandardMaterial3D)
  assert ?material, "BotNode material must be StandardMaterial3D"

  material[].albedo_color = godot_color

  # Set transparency mode if alpha is less than 1
  if adjusted.a < 1.0:
    material[].transparency = BaseMaterial3D_Transparency.transparencyAlpha

proc set_visibility(self: BotNode) =
  assert ?self.model, "BotNode model must be available for visibility setting"

  var color = self.model.color
  let visible_flag = Visible in self.model.global_flags
  let god_mode = God in state.local_flags

  if visible_flag:
    self.set_visible(true)
    self.set_color(color)
  elif not visible_flag and god_mode:
    self.set_visible(true)
    # Set fully transparent color for god mode (matching Godot 3)
    color.a = 0.0
    let material = self.material.as(gdref StandardMaterial3D)
    assert ?material, "BotNode material must be StandardMaterial3D for god mode"

    material[].transparency = BaseMaterial3D_Transparency.transparencyAlpha
    let godot_color = gdext.color(color.r, color.g, color.b, color.a)
    material[].albedo_color = godot_color
  else:
    self.set_visible(false)

proc set_walk_animation(self: BotNode, velocity: float, backwards: bool) =
  if ?self.animation_player:
    if velocity <= 0.1:
      # Play idle animation with slower speed
      self.animation_player.set_speed_scale(0.5)
      self.animation_player.play(newStringName("idle"), 0.5) # custom_blend = 0.5
    elif velocity < 5:
      # Play walk animation with speed based on velocity
      self.animation_player.set_speed_scale(velocity / 2.0)
      if backwards:
        # TODO: Implement play_backwards when gdext supports it
        self.animation_player.play(newStringName("walk"), 0.1)
          # custom_blend = 0.1
      else:
        self.animation_player.play(newStringName("walk"), 0.1)
          # custom_blend = 0.1
    else:
      # Play run animation
      self.animation_player.set_speed_scale(velocity / 10.0)
      let anim_name = if backwards: "run_backwards" else: "run"
      self.animation_player.play(newStringName(anim_name), 0.1)
        # custom_blend = 0.1

proc track_changes(self: BotNode) =
  assert ?self.model, "BotNode model must be available for change tracking"

  # Transform tracking - critical for bot movement
  self.transform_zid = self.model.transform_value.watch:
    if added:
      self.set_transform(change.item)

  # Visibility tracking - only update when not initializing to prevent flicker
  self.model.global_flags.watch:
    if (
      change.item == Visible and ScriptInitializing notin self.model.global_flags
    ) or ScriptInitializing.removed:
      self.set_visibility()

  # Color tracking
  self.model.color_value.watch:
    if added:
      self.set_color(change.item)

  # Scale tracking
  self.model.scale_value.watch:
    if added:
      let scale = change.item
      self.set_scale(vector3(scale, scale, scale))
      # Also update model transform to stay in sync
      self.model.transform_value.pause(self.transform_zid):
        self.model.transform = self.get_transform()

  # Highlighting
  self.model.local_flags.watch:
    if Highlight.added:
      self.highlight()
    elif Highlight.removed:
      self.set_default_material()

  # God mode visibility
  state.local_flags.watch:
    if change.item == God:
      self.set_visibility()

  # Bot-specific tracking
  if self.model of Bot:
    let bot = Bot(self.model)
    # Velocity tracking for walk animations
    bot.velocity_value.watch:
      if touched:
        if bot.animation == "auto":
          self.set_walk_animation(change.item.length, false)

    # Animation tracking
    bot.animation_value.watch:
      if added or (touched and change.item in ["", "auto"]):
        self.animation_player.play(newStringName("idle"), 0.5) # Add blend
      elif added:
        self.animation_player.play(newStringName(change.item), 0.1) # Add blend

proc setup*(self: BotNode) =
  assert ?self.model, "BotNode model must be available for setup"

  self.set_color(self.model.color)
  self.track_changes()
  # Initial visibility check
  self.set_visibility()

  # Set up sight ray - it's optional for bots
  let sight_ray = self.find_child("SightRay", false, false).as(RayCast3D)
  if ?sight_ray:
    # TODO: Set model sight ray when Unit model API is available
    discard

method physics_process*(self: BotNode, delta: float64) {.gdsync.} =
  # Godot 4 uses physics_process for CharacterBody3D movement
  # Model can be nil during initialization, that's expected
  if ?self.model:
    # Bidirectional sync: update model transform from node transform if this thread owns the model
    if self.model.code.owner == state.worker_ctx_name:
      self.model.transform_value.pause(self.transform_zid):
        self.model.transform = self.get_transform()

    # Handle bot movement
    if self.model of Bot:
      let bot = Bot(self.model)
      if bot.velocity.length > 0:
        # Use Godot 4 CharacterBody3D movement
        self.set_velocity(bot.velocity)
        discard self.move_and_slide()

var bot_scene {.threadvar.}: gdref PackedScene

proc init*(_: type BotNode): BotNode =
  let resource = ResourceLoader.load("res://components/BotNode.tscn")
  bot_scene = resource.as(gdref PackedScene)
  assert ?bot_scene, "BotNode.tscn must be loadable"

  let instance = bot_scene[].instantiate()
  result = cast[BotNode](instance)
