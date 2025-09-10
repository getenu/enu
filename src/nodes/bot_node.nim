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
import core, gdutils, models/colors, ui/markdown_label
import queries

type BotNode* {.gdsync.} =
  ptr object of CharacterBody3D
    model*: Unit
    material*: gdref Material
    highlight_material*: gdref Material
    selected_material*: gdref Material
    skin: Node3D
    mesh: MeshInstance3D
    animation_player: AnimationPlayer
    animation_tree: AnimationTree
    transform_zid: ZID

proc update_material*(self: BotNode, value: gdref Material) =
  if ?self.mesh and ?value:
    self.mesh.set_surface_override_material(0, value)
    print("[BOT] Material updated")

proc set_default_material(self: BotNode) =
  if ?self.material:
    self.update_material(self.material)

proc highlight(self: BotNode) =
  if ?self.highlight_material:
    self.update_material(self.highlight_material)

method ready*(self: BotNode) {.gdsync.} =
  print("[BOT] BotNode initializing")

  # Find child nodes
  self.skin = self.find_child("model", false, false).as(Node3D)
  if ?self.skin:
    self.mesh = self.skin.find_child("body001", false, false).as(MeshInstance3D)
    self.animation_player =
      self.skin.find_child("AnimationPlayer", false, false).as(AnimationPlayer)
    self.animation_tree =
      self.skin.find_child("AnimationTree", false, false).as(AnimationTree)

    if ?self.mesh:
      self.set_default_material()
      print("[BOT] Mesh and material configured")
    else:
      print("[BOT] ✗ Mesh not found")

    if ?self.animation_player:
      print("[BOT] AnimationPlayer found")
    else:
      print("[BOT] ✗ AnimationPlayer not found")

    if ?self.animation_tree:
      # Disable AnimationTree so we can use AnimationPlayer directly like Godot 3
      self.animation_tree.set_active(false)
      print("[BOT] AnimationTree found and disabled")
    else:
      print("[BOT] ⚠️ AnimationTree not found")

    # Adjust player model position  
    if ?self.model and self.model of Player:
      # hack so player model doesn't hover
      let current_pos = self.skin.get_position()
      self.skin.set_position(current_pos + vector3(0, -0.8, 0))
      print("[BOT] Player model position adjusted (moved down by 0.8)")
  else:
    print("[BOT] ✗ Skin model not found")

  print("[BOT] BotNode ready")

proc set_color(self: BotNode, color: chroma.Color) =
  if ?self.mesh and ?self.material:
    # Get the material (create a copy if needed to avoid modifying shared materials)
    let material = self.material[].duplicate().as(gdref StandardMaterial3D)
    if ?material:
      # Convert chroma Color to Godot Color
      let godot_color = gdext.color(color.r, color.g, color.b, 1.0)
      material[].set_albedo(godot_color)

      # Apply the modified material
      self.mesh.set_surface_override_material(0, material.as(gdref Material))
      print("[BOT] Color set to: (", color.r, ", ", color.g, ", ", color.b, ")")
    else:
      print("[BOT] ✗ Could not cast material to StandardMaterial3D")
  else:
    print("[BOT] ✗ Cannot set color - missing mesh or material")

proc set_visibility(self: BotNode) =
  if ?self.model:
    let visible_flag = Visible in self.model.global_flags
    let god_mode = God in state.local_flags

    if visible_flag:
      self.set_visible(true)
      self.set_color(self.model.color)
    elif not visible_flag and god_mode:
      self.set_visible(true)
      # Set transparent color for god mode
      if ?self.mesh and ?self.material:
        let material = self.material[].duplicate().as(gdref StandardMaterial3D)
        if ?material:
          # Make material semi-transparent
          material[].set_transparency(
            BaseMaterial3D_Transparency.transparencyAlpha
          )
          let transparent_color = gdext.color(
            self.model.color.r, self.model.color.g, self.model.color.b, 0.3
          )
          material[].set_albedo(transparent_color)
          self.mesh.set_surface_override_material(
            0, material.as(gdref Material)
          )
          print("[BOT] God mode transparency applied")
        else:
          print("[BOT] ✗ Could not create transparent material for god mode")
      else:
        print("[BOT] ✗ Cannot apply transparency - missing mesh or material")
    else:
      self.set_visible(false)

    print("[BOT] Visibility set: ", self.is_visible())

proc set_walk_animation(self: BotNode, velocity: float, backwards: bool) =
  if ?self.animation_player:
    if velocity <= 0.1:
      # Play idle animation with slower speed
      self.animation_player.set_speed_scale(0.5)
      self.animation_player.play(newStringName("idle"))
    elif velocity < 5:
      # Play walk animation with speed based on velocity
      self.animation_player.set_speed_scale(velocity / 2.0)
      if backwards:
        # TODO: Implement play_backwards when gdext supports it
        self.animation_player.play(newStringName("walk"))
      else:
        self.animation_player.play(newStringName("walk"))
    else:
      # Play run animation
      self.animation_player.set_speed_scale(velocity / 4.0)
      let anim_name = if backwards: "run_backwards" else: "run"
      self.animation_player.play(newStringName(anim_name))

proc track_changes(self: BotNode) =
  if not ?self.model:
    print("[BOT] ✗ Cannot track changes - no model")
    return

  print("[BOT] Setting up model change tracking")

  # Transform tracking - critical for bot movement
  self.transform_zid = self.model.transform_value.watch:
    if added:
      self.set_transform(change.item)
      # Debug output disabled - working correctly
      # print("[BOT] Transform updated from model")

  # Visibility tracking - only update when not initializing to prevent flicker
  self.model.global_flags.watch:
    if (
      change.item == Visible and
      ScriptInitializing notin self.model.global_flags
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
        self.animation_player.play(newStringName("idle"))
      elif added:
        self.animation_player.play(newStringName(change.item))

  print("[BOT] Model change tracking active")

proc setup*(self: BotNode) =
  print("[BOT] Setting up BotNode")

  if ?self.model:
    self.set_color(self.model.color)
    self.track_changes()
    # Initial visibility check
    self.set_visibility()

    # Set up sight ray
    let sight_ray = self.find_child("SightRay", false, false).as(RayCast3D)
    if ?sight_ray:
      # TODO: Set model sight ray when Unit model API is available
      print("[BOT] SightRay found and would be configured")
    else:
      print("[BOT] ⚠️ SightRay not found")
  else:
    print("[BOT] ✗ Cannot setup - no model")

method physics_process*(self: BotNode, delta: float64) {.gdsync.} =
  # Godot 4 uses physics_process for CharacterBody3D movement
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
        # Debug output disabled - too spammy
        # print("[BOT] Moving with velocity: ", bot.velocity)

var bot_scene {.threadvar.}: gdref PackedScene

proc init*(_: type BotNode): BotNode =
  try:
    let resource = ResourceLoader.load("res://components/BotNode.tscn")
    bot_scene = resource.as(gdref PackedScene)
    if ?bot_scene:
      let instance = bot_scene[].instantiate()
      result = cast[BotNode](instance)
      print("[BOT] BotNode instantiated successfully")
    else:
      print("[BOT] ✗ Failed to load BotNode scene - resource is nil")
  except:
    print("[BOT] ✗ Failed to load or instantiate BotNode")
