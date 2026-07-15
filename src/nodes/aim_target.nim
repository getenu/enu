import std/[strutils, wrapnils, options]
import pkg/[godot]
import godotapi/[sprite_3d, ray_cast, spatial]
import gdutils, core, nodes/helpers, models

gdobj AimTarget of Sprite3D:
  var target_model: Model

  method ready*() =
    self.set_as_top_level(true)
    self.bind_signals "collider_exiting"
    self.visible = BLOCK_TARGET_VISIBLE in state.local_flags

    state.local_flags.watch(state.player):
      if BLOCK_TARGET_VISIBLE.added:
        self.visible = true
      elif BLOCK_TARGET_VISIBLE.removed:
        self.visible = false

    state.tool_value.watch(state.player):
      # tool changed. Retarget.
      if self.target_model != nil:
        self.target_model.local_flags -= HOVER
        self.target_model.target_point = vec3()
        self.target_model.target_normal = vec3()
        self.target_model = nil

  proc update*(ray: RayCast) =
    ray.force_raycast_update()
    let collider =
      if ray.is_colliding():
        ray.get_collider() as Spatial
      else:
        nil

    let thing = ?.collider.model

    # Invisible walls collide (so they block the ray) but must not show the aim
    # target. Sample the voxel just inside the hit face; if it's INVISIBLE, treat
    # the hit as untargetable — hide the sprite and don't hover/target it.
    var hit_invisible = false
    if collider != nil and thing of Build:
      let inside = collider.to_local(
        ray.get_collision_point() - ray.get_collision_normal() * 0.5
      )
      let info = Build(thing).find_voxel(inside.floor)
      hit_invisible = info.is_some and info.get.color == ACTION_COLORS[INVISIBLE]

    if hit_invisible:
      if self.target_model != nil:
        self.target_model.local_flags -= HOVER
        self.target_model.target_point = vec3()
        self.target_model.target_normal = vec3()
        state.pop_flag BLOCK_TARGET_VISIBLE
        self.target_model = nil
      self.visible = false
      return

    if ?self.target_model:
      # :(
      if ?self.target_model.global_flags and
          self.target_model.global_flags.destroyed:
        self.target_model = nil
      elif ?self.target_model.local_flags and
          self.target_model.local_flags.destroyed:
        self.target_model = nil

    if thing != self.target_model:
      if self.target_model != nil:
        self.target_model.local_flags -= HOVER
        state.pop_flag BLOCK_TARGET_VISIBLE
      self.target_model = thing
      # Locked builds still hover and show the aim target — clicking them
      # places into a NEW thing, like clicking the ground (see Build.fire).
      # Locked bots stay inert.
      if not (
        thing == nil or (thing of Sign and Sign(thing).more == "") or (
          GOD notin state.local_flags and thing of Bot and
          LOCK in Thing(thing).find_root.global_flags
        )
      ):
        thing.local_flags += HOVER
        if thing of Build or thing of Ground:
          state.push_flag BLOCK_TARGET_VISIBLE

    if collider != nil:
      var
        global_normal = ray.get_collision_normal()
        local_point: Vector3
      let
        local_collision_point = collider.to_local(ray.get_collision_point())
        basis = collider.global_transform.basis
        half = vec3(0.5, 0.5, 0.5)
        local_normal =
          (basis.xform_inv(global_normal) / collider.scale).snapped(half)
        factor = local_normal.inverse_normalized() * 0.5

      if not local_normal.is_axis_aligned:
        # All local normals should be axis aligned because we're dealing with cubes.
        # If it isn't, we probably got a corner or something.
        return

      local_point =
        (local_collision_point - factor).snapped(vec3(1, 1, 1)) + factor
      global_normal = basis.xform(local_normal) / collider.scale

      self.translation =
        collider.to_global local_point + (local_normal * 0.01) / collider.scale
      self.scale = collider.scale

      let align_normal = self.transform.origin + global_normal
      self.look_at(align_normal, self.transform.basis.x)

      if ?thing:
        if (thing.target_point, thing.target_normal) != (
          local_point, local_normal
        ):
          thing.target_point = local_point
          thing.target_normal = local_normal
          thing.local_flags.touch TARGET_MOVED
        else:
          thing.local_flags -= TARGET_MOVED
    else:
      state.skip_block_paint = false

  method on_collider_exiting(collider: Spatial) =
    if collider.model == self.target_model:
      self.target_model = nil
