import std/[strutils, wrapnils, options]
import pkg/[godot]
import godotapi/[sprite_3d, ray_cast, spatial, input, global_constants]
import gdutils, core, nodes/helpers, models

type JoinKey = tuple[
  model: Model,
  cell: Vector3,
  tool: Tools,
  last, drag: Build,
  choice: CreateChoice,
  held: bool,
]

gdobj AimTarget of Sprite3D:
  var
    target_model: Model
    glowing: Build
    join_key: JoinKey
    held_to: Transform ## Where the held thing goes if it's put down now.
    held_from: Transform ## Where the held thing was, in the world.
    aim_point: Vector3 ## Where the aim last hit something.
    grab: Vector3 ## Where the aim hit the held thing when it was picked up.

  proc glow(target: Build) =
    if target != self.glowing:
      if ?self.glowing and not self.glowing.local_flags.destroyed:
        self.glowing.local_flags -= JOIN_TARGET
      if ?target:
        target.local_flags += JOIN_TARGET
      self.glowing = target

  proc update_glow(thing: Model) =
    ## Light up the unit a block placed now would go to.
    let tool = state.player.tool
    if tool notin BLOCK_TOOLS or PLAYING in state.player.flags or thing.is_nil or
        HOVER notin thing.local_flags or not (thing of Build or thing of Ground):
      self.join_key = JoinKey.default
      self.glow(nil)
      refresh_create_mode()
      return
    let cell =
      if thing of Build:
        Build(thing).placement_cell
      else:
        Ground(thing).placement_cell
    let key: JoinKey = (
      thing, cell, tool, last_edited, stroke.target, create_choice, create_held
    )
    if key == self.join_key:
      return
    self.join_key = key
    self.glow(
      if stroke.active and ?stroke.target:
        stroke.target
      else:
        aim_at(thing, cell)
    )

  method ready*() =
    self.set_as_top_level(true)
    self.bind_signals "collider_exiting"
    self.visible = BLOCK_TARGET_VISIBLE in state.local_flags

    state.local_flags.watch(state.player):
      if BLOCK_TARGET_VISIBLE.added:
        self.visible = true
      elif BLOCK_TARGET_VISIBLE.removed:
        self.visible = false

    state.local_flags.watch(state.player):
      if PRIMARY_DOWN.added and VIEWPORT_FOCUSED in state.local_flags:
        if ?held:
          put_down(self.held_to)
        elif state.player.tool in THING_TOOLS and self.target_model of Thing and
            Thing(self.target_model).can_hold:
          hold(Thing(self.target_model))
          self.held_to = held.transform
          self.held_from = (held.node as Spatial).global_transform
          self.grab = self.aim_point

    state.player.tool_value.watch(state.player):
      put_back()
      # tool changed. Retarget.
      if self.target_model != nil:
        self.target_model.local_flags -= HOVER
        self.target_model.target_point = vec3()
        self.target_model.target_normal = vec3()
        self.target_model = nil

  proc place_held(to: Transform) =
    let node = held.node as Spatial
    node.global_transform = to
    self.held_to = node.transform

  proc carry_held(thing: Model) =
    ## Keep the move tool's held thing on the block the aim is on.
    let cell =
      if thing of Build:
        Build(thing).placement_cell
      elif thing of Ground:
        Ground(thing).placement_cell
      else:
        return
    var to = (held.node as Spatial).global_transform
    to.origin =
      if held of Bot:
        cell + vec3(0.5, 0, 0.5)
      else:
        cell - to.basis.xform(held.anchor.origin)
    self.place_held(to)

  proc lift_held(ray: RayCast) =
    ## Raise or lower the lift tool's held thing to the aim's height.
    let
      eye = ray.global_transform.origin
      look = ray.global_transform.basis.xform(ray.cast_to).normalized
      to = lifted(self.held_from, self.grab, eye, look)
    if to.is_some:
      self.place_held(to.get)

  proc update*(ray: RayCast) =
    create_held =
      is_key_pressed(if host_os == "macosx": KEY_META else: KEY_CONTROL)
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
      self.update_glow(nil)
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
          GOD notin state.player.flags and thing of Bot and
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

    if collider != nil:
      self.aim_point = ray.get_collision_point()
    if ?held and state.player.tool == MOVE_TOOL and collider != nil:
      self.carry_held(thing)
    elif ?held and state.player.tool == LIFT_TOOL:
      self.lift_held(ray)
    self.update_glow(thing)

    if PRIMARY_DOWN notin state.local_flags and
        SECONDARY_DOWN notin state.local_flags:
      end_stroke()
    elif VIEWPORT_FOCUSED notin state.local_flags:
      discard
    elif thing of Build:
      Build(thing).stroke_frame()
    elif thing of Ground:
      Ground(thing).stroke_frame()
    else:
      discard stroke_miss()

  method on_collider_exiting(collider: Spatial) =
    if collider.model == self.target_model:
      self.target_model = nil
