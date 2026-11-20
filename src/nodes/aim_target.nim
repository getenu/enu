import std/[strutils, wrapnils, options]
import pkg/[godot]
import godotapi/[sprite_3d, ray_cast, spatial, input, global_constants]
import gdutils, core, nodes/helpers, models

when defined(enu_web):
  import godotapi/static_body
  import nodes/[sign_node, sign_web]

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
    page_sign_id: string # the sign page under the pointer (-d:enu_web)
    page_down: bool

  proc forward_pointer(collider: Spatial, ray: RayCast) =
    ## Signs that are pages get the pointer: moves for `:hover`, and the
    ## primary button for clicks.
    when defined(enu_web):
      let sign_node =
        if collider != nil and collider of StaticBody and
            collider.name == "SignBody":
          SignNode(collider.get_parent.get_parent)
        else:
          nil
      let point = ray.get_collision_point()
      let on_page =
        sign_node != nil and sign_node.page_pointer(POINTER_MOVE, point)
      let id = if on_page: sign_node.model.id else: ""
      if id != self.page_sign_id:
        if self.page_sign_id != "":
          discard ew_post_pointer(self.page_sign_id.cstring, POINTER_LEAVE, 0, 0)
        self.page_sign_id = id
        self.page_down = false
      if on_page:
        let down = PRIMARY_DOWN in state.local_flags
        if down != self.page_down:
          discard sign_node.page_pointer(if down: POINTER_DOWN else: POINTER_UP, point)
          self.page_down = down

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

    state.player.tool_value.watch(state.player):
      # tool changed. Retarget.
      if self.target_model != nil:
        self.target_model.local_flags -= HOVER
        self.target_model.target_point = vec3()
        self.target_model.target_normal = vec3()
        self.target_model = nil

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

    when defined(enu_web):
      self.forward_pointer(collider, ray)

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
