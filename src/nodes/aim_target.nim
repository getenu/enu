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

import std/[strutils, options, wrapnils]
import gdext
import
  gdext/classes/
    [gdsprite3d, gdraycast3d, gdnode3d, gdpackedscene, gdresourceloader]

import core, gdcore, models
import ./[ground_node, build_node, bot_node, sign_node, helpers]

type AimTarget* {.gdsync.} =
  ptr object of Sprite3D
    target_model*: Model

method ready*(self: AimTarget) {.gdsync.} =
  self.set_as_top_level(true)
  # TODO: Restore signal binding when character encoding is fixed
  # self.bind_signals "collider_exiting"
  # Initialize visibility based on BlockTargetVisible flag (matching Godot 3)
  if not state.is_nil:
    self.set_visible(BlockTargetVisible in state.local_flags)

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

  # Use the helpers.nim model accessor just like Godot 3
  let unit = if ?collider: collider.model else: nil

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
      if not state.is_nil:
        state.pop_flag BlockTargetVisible
    self.target_model = unit

    # Restore Godot 3 hover logic
    if ?unit:
      # Handle Ground models separately since they don't inherit from Unit
      if unit of Ground:
        unit.local_flags += Hover
        if not state.is_nil:
          state.push_flag BlockTargetVisible
      else:
        # Handle Unit models (Bot, Build, Sign) with Godot 3 logic
        let should_hide = (
          (unit of Sign and Sign(unit).more == "") or (
            not state.is_nil and God notin state.local_flags and
            (unit of Bot or unit of Build) and ?Unit(unit).find_root and
            ?Unit(unit).find_root.global_flags and
            Lock in Unit(unit).find_root.global_flags
          )
        )

        if not should_hide:
          unit.local_flags += Hover
          if unit of Build and not state.is_nil:
            state.push_flag BlockTargetVisible

  # Position the aim target at collision point with proper orientation and snapping
  if ?collider:
    var global_normal = ray.get_collision_normal()
    var local_point: Vector3

    let local_collision_point = collider.to_local(ray.get_collision_point())
    let basis = collider.global_transform.basis
    let half = vector3(0.5, 0.5, 0.5)

    # Calculate local normal - need to handle scale
    let scale = collider.scale
    let inv_scale = vector3(1.0 / scale.x, 1.0 / scale.y, 1.0 / scale.z)

    # Transform global normal to local space and snap it
    var local_normal = basis.inverse() * global_normal
    local_normal = (local_normal * inv_scale).snapped(half)

    # Helper function to check if a vector component is close to a value
    proc is_close(a, b: float, tolerance = 0.01): bool =
      abs(a - b) < tolerance

    # Check if normal is axis-aligned (matching Godot 3 logic)
    let is_axis_aligned =
      (
        is_close(abs(local_normal.x), 1.0) and is_close(local_normal.y, 0.0) and
        is_close(local_normal.z, 0.0)
      ) or (
        is_close(local_normal.x, 0.0) and is_close(abs(local_normal.y), 1.0) and
        is_close(local_normal.z, 0.0)
      ) or (
        is_close(local_normal.x, 0.0) and is_close(local_normal.y, 0.0) and
        is_close(abs(local_normal.z), 1.0)
      )

    if not is_axis_aligned:
      # All local normals should be axis aligned because we're dealing with cubes.
      # If it isn't, we probably got a corner or something.
      return

    # Calculate factor for positioning (matching Godot 3's inverse_normalized logic)
    let factor = local_normal.inverse_normalized() * 0.5

    # Snap the local point to grid (1x1 squares)
    local_point =
      (local_collision_point - factor).snapped(vector3(1, 1, 1)) + factor

    # Transform local normal back to global space
    global_normal = (basis * local_normal) * inv_scale

    # Position the aim target with snapping
    let local_offset = local_point + (local_normal * 0.01) * inv_scale
    let target_pos_arr = collider.to_global(local_offset)
    let target_pos =
      vector3(target_pos_arr[0], target_pos_arr[1], target_pos_arr[2])
    self.global_position = target_pos_arr
    self.scale = collider.scale

    # Orient the sprite to lay flat on the surface (matching Godot 3 look_at behavior)
    let global_normal_vec =
      vector3(global_normal[0], global_normal[1], global_normal[2])
    let align_normal = vector3(
      target_pos.x + global_normal_vec.x,
      target_pos.y + global_normal_vec.y,
      target_pos.z + global_normal_vec.z,
    )

    # In Godot 3, the look_at uses self.transform.basis.x as the up vector
    # This orients the sprite to face along the normal with the X-axis as up
    self.look_at(align_normal, self.transform.basis.get_column_x())

    # Only show the aim target if BlockTargetVisible flag is set (matching Godot 3 logic)
    if not state.is_nil:
      self.set_visible(BlockTargetVisible in state.local_flags)

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
    if not state.is_nil:
      state.skip_block_paint = false

# TODO: Restore when signal binding works
# method on_collider_exiting*(self: AimTarget, collider: Node3D) {.gdsync.} =
#   if ?collider and collider.model == self.target_model:
#     self.target_model = nil

proc init*(_: type AimTarget): AimTarget =
  let scene = cast[gdref PackedScene](ResourceLoader.load(
    "res://components/AimTarget.tscn"
  ))
  if ?scene:
    result = cast[AimTarget](scene[].instantiate())
