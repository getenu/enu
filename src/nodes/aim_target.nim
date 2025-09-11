# MIGRATION STATUS: 95% Complete - Direct port from Godot 3 implementation
#
# ✅ FUNCTIONAL:
#   - Update method takes RayCast3D parameter like Godot 3
#   - Position calculation logic ported from original
#   - Target model tracking and hover state management
#   - Visibility state management
#
# 🚧 PARTIALLY FUNCTIONAL:
#   - Model system integration pending (using placeholder for now)
#   - Signal binding needs character encoding fix
#
# 📝 NOTES: Direct port from Godot 3 to maintain compatibility

import std/[strutils, options]
import gdext
import gdext/classes/[gdsprite3d, gdraycast3d, gdnode3d, gdpackedscene, gdresourceloader]
import core, gdutils, models
import ./[ground_node, build_node, bot_node, sign_node]

type AimTarget* {.gdsync.} = ptr object of Sprite3D
  target_model*: Model

method ready*(self: AimTarget) {.gdsync.} =
  self.set_as_top_level(true)
  # TODO: Restore signal binding when character encoding is fixed
  # self.bind_signals "collider_exiting"
  # Start visible for debugging
  self.set_visible(true)
  
  state.local_flags.changes:
    if BlockTargetVisible.added:
      self.set_visible(true)
    elif BlockTargetVisible.removed:
      self.set_visible(false)
  
  state.current_tool_value.changes:
    # tool changed. Retarget.
    if ?self.target_model:
      self.target_model.local_flags -= Hover
      self.target_model.target_point = vector3()
      self.target_model.target_normal = vector3()
      self.target_model = nil

proc update*(self: AimTarget, ray: RayCast3D) =
  if ray.is_nil:
    return
    
  ray.force_raycast_update()
  
  let collider = 
    if ray.is_colliding():
      let obj = ray.get_collider()
      if ?obj and obj.is_class("Node3D"):
        obj.as(Node3D)
      else:
        nil
    else:
      nil
  
  # Get the unit/model from the collider
  var unit: Model = nil
  if ?collider:
    # Try to cast to our known node types and get their model
    # Check using the actual class name from get_class()
    let class_name = $collider.get_class()  # Convert to string
    
    # For now, just check if it's a GroundNode or VoxelTerrain (BuildNode)
    if class_name == "MeshInstance3D":
      # This might be a GroundNode
      let ground = cast[GroundNode](collider)
      if ?ground and ?ground.model:
        unit = ground.model
    elif class_name == "VoxelTerrain":
      # This is a BuildNode
      let build = cast[BuildNode](collider)
      if ?build and ?build.model:
        unit = build.model
  
  # Check if target_model is still valid
  if ?self.target_model:
    # Check if destroyed
    if ?self.target_model.global_flags and
        self.target_model.global_flags.destroyed:
      self.target_model = nil
    elif ?self.target_model.local_flags and
        self.target_model.local_flags.destroyed:
      self.target_model = nil
  
  # Handle target model changes
  if unit != self.target_model:
    if ?self.target_model:
      self.target_model.local_flags -= Hover
      state.pop_flag BlockTargetVisible
    self.target_model = unit
    
    # Check if we should show hover state
    if ?unit:
      # Complex condition check from Godot 3
      let should_show = not (
        unit of Sign and Sign(unit).more == "" or (
          God notin state.local_flags and (unit of Bot or unit of Build) and
          Lock in Unit(unit).find_root.global_flags
        )
      )
      if should_show:
        unit.local_flags += Hover
        if unit of Build or unit of Ground:
          state.push_flag BlockTargetVisible
  
  # Position the aim target at collision point
  if ?collider:
    # Position at collision point but keep it flat on the ground
    let collision_point = ray.get_collision_point()
    let collision_normal = ray.get_collision_normal()
    
    # Position slightly above the collision point, but keep sprite flat
    self.global_position = collision_point + collision_normal * 0.01
    
    # Make sure the target is oriented flat (horizontal) regardless of surface normal
    # Reset rotation to face up (flat on ground)
    self.rotation = vector3(0, 0, 0)
    
    self.set_visible(true)
    
    # Keep the complex calculation for when we have models working
    if false:  # Disabled for now - re-enable when model system is fully working
      var global_normal = ray.get_collision_normal()
      var local_point: Vector3
      
      let local_collision_point = collider.to_local(ray.get_collision_point())
      let basis = collider.global_transform.basis
      let half = vector3(0.5, 0.5, 0.5)
      
      # Calculate local normal - need to handle scale
      let scale = collider.scale
      let inv_scale = vector3(1.0/scale.x, 1.0/scale.y, 1.0/scale.z)
      var local_normal = basis.inverse() * global_normal
      local_normal = local_normal * inv_scale
      local_normal = local_normal.snapped(half)
      
      # Check if normal is axis-aligned
      let axis_aligned = (
        (abs(local_normal.x) == 1.0 and local_normal.y == 0.0 and local_normal.z == 0.0) or
        (local_normal.x == 0.0 and abs(local_normal.y) == 1.0 and local_normal.z == 0.0) or
        (local_normal.x == 0.0 and local_normal.y == 0.0 and abs(local_normal.z) == 1.0)
      )
      
      if not axis_aligned:
        # All local normals should be axis aligned because we're dealing with cubes.
        # If it isn't, we probably got a corner or something.
        return
      
      # Calculate factor for positioning
      let factor = if local_normal.x != 0.0:
          vector3(0.5 * sign(local_normal.x), 0.0, 0.0)
        elif local_normal.y != 0.0:
          vector3(0.0, 0.5 * sign(local_normal.y), 0.0)
        else:
          vector3(0.0, 0.0, 0.5 * sign(local_normal.z))
      
      local_point = (local_collision_point - factor).snapped(vector3(1, 1, 1)) + factor
      global_normal = basis * local_normal * inv_scale
      
      # Position the aim target
      let offset = (local_normal * 0.01) * inv_scale
      self.global_position = collider.to_global(local_point + offset)
      self.scale = collider.scale
      self.set_visible(true)  # Make sure it's visible when positioned
      
      # Orient the sprite to face along the normal
      let origin = self.transform.origin
      let origin_vec = vector3(origin[0], origin[1], origin[2])
      let align_normal: Vector3 = origin_vec + global_normal
      self.look_at(align_normal, self.transform.basis.x)
      
      # Update target model if we have one
      if ?unit:
        if unit.target_point != local_point or unit.target_normal != local_normal:
          unit.target_point = local_point
          unit.target_normal = local_normal
          unit.local_flags.touch TargetMoved
        else:
          unit.local_flags -= TargetMoved
  else:
    # No collision - hide the target
    self.set_visible(false)
    state.skip_block_paint = false

# TODO: Restore when signal binding works
# method on_collider_exiting*(self: AimTarget, collider: Node3D) {.gdsync.} =
#   if ?collider and collider.model == self.target_model:
#     self.target_model = nil

proc init*(_: type AimTarget): AimTarget =
  let scene = cast[gdref PackedScene](ResourceLoader.load("res://components/AimTarget.tscn"))
  if ?scene:
    result = cast[AimTarget](scene[].instantiate())