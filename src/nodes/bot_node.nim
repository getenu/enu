import std/[tables, math, os, options]
import pkg/godot except print
import pkg/[chroma]
import
  godotapi/[
    scene_tree, kinematic_body, material, mesh_instance, spatial, input_event,
    animation_player, resource_loader, packed_scene, spatial_material,
    text_edit, camera, viewport, texture, image, visual_server, voxel_viewer,
    area, ray_cast,
  ]
import gdutils, core, models/[colors, units, builds], ui/markdown_label
import ./queries

const climb_speed = 10.0
  ## How fast a bot rises onto a block (units/sec) — the climb is animated at
  ## this rate (~0.1s per block) instead of snapping; the drop back down is
  ## animated by gravity.

const foot_offset = 0.0
  ## How far a bot's origin sits above the surface it stands on — the target for
  ## the vertical floor-follow (surface top + this). The bot's feet are AT its
  ## origin (the collision capsule spans 0..1.75 upward from it), verified
  ## visually: origin = surface top reads as standing; +1 floats a full voxel.

proc solid_at(build: Build, cell: Vector3): bool =
  ## Is this build-local grid cell a solid (standable) voxel?
  if cell notin build:
    return false
  let info = build.voxel_info(cell)
  info.kind != HOLE and info.color != ACTION_COLORS[ERASER]

const SELF_AVATAR_LAYER = 1'i64 shl 19
  ## Render layer for the local player's own avatar: the player's first-person
  ## camera culls it (you never see your own body), every other camera draws
  ## it, and shadow casting is unaffected — so you still see your own shadow.

gdobj BotNode of KinematicBody:
  var
    model* {.cursor.}: Unit
    material* {.gdExport.},
      highlight_material* {.gdExport.},
      selected_material* {.gdExport.}: Material
    skin: Spatial
    mesh: MeshInstance
    animation_player: AnimationPlayer
    transform_zid: EID
    # A screenshot query is multi-phase: positioning the camera doesn't take
    # effect until the next render, and a projection-mode change (ortho ↔
    # perspective) needs an extra frame on top of that. -1 = idle, N > 0 =
    # warming up (decrement each frame), 0 = capture this frame.
    screenshot_warmup_frames: int = -1
    # Bot hides its own skin during capture so it doesn't fill its own POV
    # when the camera sits near the bot's body (screenshot, screenshot_at).
    skin_hidden_during_screenshot: bool
    # Platform transform-matching: carry the bot by the rigid motion of the build
    # under its feet (rotation + translation) so it rides a moving/turning
    # platform while staying a world-space body — its coordinates never change.
    # The floor is found by querying voxel data (not a physics ray: colliders
    # are only cooked near viewers, so a ray finds nothing away from the player
    # and the bot would fall through the world). We track the floor node's id +
    # world transform to apply each frame's delta.
    floor_prev_id: int64
    floor_prev_transform: Transform
    fall_velocity: float # node-side fake gravity for walking off ledges
    floor_seen: bool # gravity only starts once the bot has stood on something

  proc update_material*(value: Material) =
    self.mesh.set_surface_material(0, value)

  proc set_default_material() =
    self.update_material(self.material)

  proc highlight() =
    self.update_material(self.highlight_material)

  method ready() =
    self.skin = self.get_node("model").as(Spatial)
    self.mesh = self.skin.get_node("root/Skeleton/body001").as(MeshInstance)
    self.set_default_material()
    self.animation_player =
      self.skin.get_node("AnimationPlayer").as(AnimationPlayer)
    if self.model of Player:
      # hack so player model doesn't hover
      self.skin.translate DOWN * 0.8

  proc set_color(color: chroma.Color) =
    var adjusted: chroma.Color
    if color == ACTION_COLORS[GREEN]:
      adjusted = color
      adjusted.a = 0.015
    elif color == ACTION_COLORS[WHITE]:
      adjusted = color
      adjusted.a = 0.1
    else:
      var dist = (color.distance(ACTION_COLORS[BROWN]) + 10).cbrt / 7.5
      adjusted = color.saturate(0.2).darken(dist - 0.15)
      adjusted.a = 0.95 - color.distance(ACTION_COLORS[BLACK]) / 100

    debug "setting bot color", color, adjusted
    SpatialMaterial(self.material).albedo_color = adjusted

  proc set_visibility() =
    var color = self.model.color
    if VISIBLE in self.model.global_flags:
      self.visible = true
      self.set_color(color)
    elif VISIBLE notin self.model.global_flags and GOD in state.local_flags:
      self.visible = true
      color.a = 0.0
      SpatialMaterial(self.material).albedo_color = color
    else:
      self.visible = false

  proc set_walk_animation(velocity: float, backwards: bool) =
    if velocity <= 0.1:
      self.animation_player.playback_speed = 0.5
      self.animation_player.play("idle", custom_blend = 0.5)
    elif velocity < 5:
      self.animation_player.playback_speed = velocity / 2
      if backwards:
        self.animation_player.play_backwards("walk", custom_blend = 0.1)
      else:
        self.animation_player.play("walk", custom_blend = 0.1)
    else:
      self.animation_player.playback_speed = velocity / 10
      if backwards:
        self.animation_player.play_backwards("run", custom_blend = 0.1)
      else:
        self.animation_player.play("run", custom_blend = 0.1)

  proc track_changes() =
    self.model.glow_value.watch:
      if added:
        if change.item >= 1.0:
          self.highlight()
        else:
          self.set_default_material()

    self.model.global_flags.watch:
      if (
        change.item == VISIBLE and
        SCRIPT_INITIALIZING notin self.model.global_flags
      ) or SCRIPT_INITIALIZING.removed:
        self.set_visibility

    self.model.local_flags.watch:
      if HIGHLIGHT.added:
        self.highlight()
      elif HIGHLIGHT.removed:
        self.set_default_material()

    state.local_flags.watch:
      if change.item == GOD:
        self.set_visibility

    var velocity_zid: EID
    if self.model of Bot:
      let bot = Bot(self.model)
      velocity_zid = bot.velocity_value.watch:
        if touched:
          if bot.animation == "auto":
            self.set_walk_animation(change.item.length, false)
      bot.animation_value.watch:
        if added or touched and change.item in ["", "auto"]:
          self.animation_player.play("idle")
        elif added:
          self.animation_player.play(change.item)
    elif self.model of Player:
      let player = Player(self.model)
      player.rotation_value.watch:
        if added:
          self.skin.rotation_degrees = (change.item + 180.0) * UP

      player.velocity_value.watch:
        if added:
          var velocity = change.item.length
          self.set_walk_animation(
            change.item.length, player.input_direction.z > 0.0
          )

      player.cursor_position_value.watch:
        # Only a BotNode carrying the code-popup sign has this editor; the
        # local player's self-avatar (and plain bots) don't, so this is a
        # no-op for them. Without the guard, the avatar — bound to the local
        # player's model — would deref a nil node the moment the editor
        # cursor moves and take the process down.
        if added and self.has_node("SignNode/Viewport/TextEdit"):
          let editor = self.get_node("SignNode/Viewport/TextEdit") as TextEdit
          editor.cursor_set_line(change.item.line, true)
          editor.cursor_set_column(change.item.col, true)

    # Scale is composed into transform.basis by `scale=` and applied via the
    # transform_value watch below — no separate node-scale writeback (it used
    # to race with rotation).

    self.model.color_value.watch:
      if added:
        self.set_color(change.item)

    self.transform_zid = self.model.transform_value.watch:
      if added:
        self.transform = change.item

    self.model.sight_query_value.watch:
      if added:
        var query = change.item
        query.run(self.model)
        self.model.sight_query = query

  proc setup*() =
    self.set_color(self.model.color)
    self.track_changes
    self.model.sight_ray = self.get_node("SightRay") as RayCast

    if self.model of Bot:
      let bot = Bot(self.model)

      # Unit queries are answered only by the server. A connected client also
      # holds the synced bot (and its query_value); answering here too makes
      # two writers race on the same synced response container — seen live as
      # an eval answered with a screenshot path.
      let serves_queries =
        EPHEMERAL in bot.global_flags and SERVER in state.local_flags
      if serves_queries:
        info "agent bot node setup",
          id = bot.id, has_query_value = ?bot.query_value
      # Bots always run both ticks: physics_process drives movement + riding (on
      # the same 60Hz tick as the platform and player, so riding is smooth), and
      # process drives the screenshot warm-up (render-tick work). Gating either on
      # SCRIPT_RUNNING used to leave non-scripted bots asleep — the node never
      # acted on the model — so they didn't ride or, on a flag/watch race, move.
      self.set_process(true)
      self.set_physics_process(true)
      # A VOXEL_VIEWER unit streams voxel terrain around itself, so screenshots
      # render even when no player is nearby. Server-side only: that's
      # where queries (and their renders) are served. (Qualified: in Nim
      # `VOXEL_VIEWER` and godot's `VoxelViewer` are the same identifier.)
      if GlobalModelFlags.VOXEL_VIEWER in bot.global_flags and
          SERVER in state.local_flags:
        let viewer = gdnew[voxel_viewer.VoxelViewer]()
        viewer.view_distance = 256
        # Meshing only — these viewers exist so screenshots render, and
        # cooking colliders along every bot's path is a main-thread cost.
        viewer.requires_collisions = false
        self.add_child(viewer)

  proc as_self_avatar*() =
    ## Make this the local player's stand-in body: inert (no collision, no
    ## per-frame process — it follows the player through the transform/rotation/
    ## velocity watches set up in `track_changes`) and on SELF_AVATAR_LAYER, so
    ## the player's own camera culls it while every other camera renders it,
    ## shadow and all.
    self.set_process(false)
    self.set_physics_process(false)
    self.collision_layer = 0
    self.collision_mask = 0
    # The body isn't the only collider: bots are targeted through their
    # SelectionArea (layer 16), which the player's aim rays hit. Left enabled,
    # the avatar — co-located with the camera — intercepts every aim, so block
    # placement, unit highlight, and code-open all resolve to the player's own
    # model. Zero its layer too so the rays pass through to the world.
    let selection = self.get_node("SelectionArea") as Area
    selection.collision_layer = 0
    self.mesh.layers = SELF_AVATAR_LAYER
    self.mesh.cast_shadow = 1 # SHADOW_CASTING_SETTING_ON
    if not state.player_camera.is_nil:
      let cam = Camera(state.player_camera)
      cam.cull_mask = cam.cull_mask and not SELF_AVATAR_LAYER

  proc process_screenshot() =
    if self.model of Bot:
      let bot = Bot(self.model)
      if EPHEMERAL in bot.global_flags and SERVER in state.local_flags:
        let q = bot.query
        if q.kind == SCREENSHOT and q.state == READY and
            self.screenshot_warmup_frames > 0:
          dec self.screenshot_warmup_frames
        elif q.kind == SCREENSHOT and q.state == READY and
            self.screenshot_warmup_frames == 0:
          let vp =
            if q.screenshot_with_ui:
              self.get_tree().root
            else:
              Viewport(state.screenshot_viewport)
          # A minimized window halts the VisualServer draw cycle, so the
          # viewport's texture would otherwise be frozen on the last frame
          # rendered before minimizing. Force a synchronous draw (no buffer
          # swap — the window may have no drawable) so the capture reflects
          # the current camera regardless of window state. `process` keeps
          # running while minimized, so the warm-up frames above committed
          # the camera transform/projection; this just renders them.
          force_draw(swap_buffers = false)
          let img = vp.get_texture.get_data
          img.flip_y
          inc state.screenshot_counter
          let path =
            get_temp_dir() /
            ("enu_screenshot_" & $state.screenshot_counter & ".png")
          discard img.save_png(path)
          info "screenshot captured", path
          self.screenshot_warmup_frames = -1
          if self.skin_hidden_during_screenshot:
            self.skin.visible = true
            self.skin_hidden_during_screenshot = false
          bot.query =
            UnitQuery(kind: SCREENSHOT, result: path, state: DONE)
        elif q.state == READY and q.kind == SCREENSHOT and
            self.screenshot_warmup_frames < 0:
          # with_ui captures the root viewport (game + GUI overlay) so the
          # camera positioning below has no effect — root is already the
          # composited screen. For without-UI we still drive the
          # screenshot camera.
          if not q.screenshot_with_ui:
            # screenshot_viewport's `world` reference is captured at game.ready
            # time, but the world changes on level switches. Refresh it
            # each shot so the ortho/perspective camera renders against
            # the current level.
            let vp = Viewport(state.screenshot_viewport)
            let main_vp = self.get_tree().root
            if not main_vp.is_nil:
              vp.world = main_vp.find_world()
            let cam = Camera(state.screenshot_camera)
            if q.screenshot_top_down:
              # Orthographic camera high above the target looking straight
              # down. Half-extent (screenshot_size) controls coverage.
              let half = if q.screenshot_size > 0: q.screenshot_size else: 30.0
              cam.set_orthogonal(half * 2, 0.1, 500.0)
              let target = self.global_transform.origin
              var t: Transform
              # Camera forward is local -Z. To look at -Y (straight down)
              # with world -Z as "image up" (so north stays at the top of
              # the frame), the local axes in world space are:
              #   local +X = world +X     (east stays right)
              #   local +Y = world -Z     (north points up in the image)
              #   local +Z = world +Y     (so local -Z = world -Y = down)
              # Row-major Basis (rows are the world-space components of
              # the local axes). Equivalent column form:
              #   local +X -> (1, 0, 0)   east stays right in the image
              #   local +Y -> (0, 0, -1)  north stays up in the image
              #   local +Z -> (0, 1, 0)   so local -Z (camera forward) = down
              # Constructing this from euler angles via init_basis(vec3(...))
              # is fragile: when pitched ±π/2 the camera ends up looking at
              # the sky.
              t.basis = init_basis(
                vec3(1, 0, 0),
                vec3(0, 0, 1),
                vec3(0, -1, 0),
              )
              # y=60 is enough headroom for anything voxel-sized while
              # staying within Enu's voxel renderer's draw distance. At
              # y=200+ the world clips and the frame goes black.
              t.origin = vec3(target.x, 60, target.z)
              cam.transform = t
            else:
              # set_perspective restores FOV/near/far if a prior top-down
              # shot left the camera in orthogonal mode.
              cam.set_perspective(70.0, 0.05, 500.0)
              var t =
                if q.screenshot_from_player and not state.player_camera.is_nil:
                  Camera(state.player_camera).global_transform
                else:
                  var bt = self.global_transform
                  bt.origin += vec3(0, 0.8, 0)
                  bt
              cam.transform = t
            cam.make_current()
            # Hide the bot's own skin so it doesn't fill the frame when
            # the camera sits at the bot's position. Skipped for the
            # from-player path since that uses the human player's camera,
            # not the bot's. Restored once the screenshot is captured.
            if not q.screenshot_from_player and not self.skin.is_nil:
              self.skin.visible = false
              self.skin_hidden_during_screenshot = true
            info "screenshot positioning camera",
              from_player = q.screenshot_from_player,
              top_down = q.screenshot_top_down,
              origin = cam.global_transform.origin
          # Two warm-up frames: one for the transform write to land, one for
          # a projection-mode change (ortho ↔ perspective) to take effect.
          # A single frame was enough most of the time but a perspective
          # capture immediately after an orthographic one occasionally read
          # back the prior frame's ortho render.
          self.screenshot_warmup_frames = 2

  proc find_floor(
      reach: float, reach_up = 0.0
  ): Option[tuple[node: Spatial, top: float32]] =
    ## The surface under the bot's feet within `reach` below them (or, with
    ## `reach_up`, embedded up to that far above them — how a walked-into step
    ## is climbed): build voxels or the world ground plane (y = 0). Queried
    ## from voxel data, NOT physics colliders — those are only cooked near
    ## viewers, so a ray finds nothing away from the player. Returns the
    ## surface's node (nil for the ground) and its world-space top height.
    let pos = self.global_transform.origin
    let feet = pos.y - foot_offset
    # Sample top-down so the highest surface wins (a step above the feet beats
    # the floor below). Half-voxel steps can't skip a full-height slab (a thin
    # *scaled-down* slab could slip through — rare, accepted).
    var dy = -reach_up
    while dy <= reach:
      let sample = vec3(pos.x, feet - 0.01 - dy, pos.z)
      for unit in state.units.value:
        if unit of Build and ?unit.node:
          let bnode = Spatial(unit.node)
          # Through the node's full transform, so rotated/scaled builds
          # (turning barges) resolve correctly — model local_to is origin-only.
          let local = bnode.global_transform.xform_inv_vector3(sample)
          let cell = vec3(floor(local.x), floor(local.y), floor(local.z))
          if Build(unit).solid_at(cell):
            let top = bnode.global_transform.xform_vector3(
              vec3(local.x, cell.y + 1.0, local.z)
            ).y
            return some((node: bnode, top: top))
      if ?state.ground and sample.y <= 0.0:
        return some((node: Spatial(nil), top: 0.0'f32))
      dy += 0.5

  proc climb_step(floor_top: float32): Option[float32] =
    ## The world top of a single climbable block directly in the bot's walking
    ## path: solid at shin height just ahead, with headroom above it (so walls
    ## two or more blocks tall still block). A walking bot needs this probe —
    ## where colliders exist (near the player) move_and_slide stops it at the
    ## block's face, so its feet never embed and find_floor's reach_up never
    ## sees the step. Anchored to the STANDING floor, not the bot's current
    ## feet: mid-climb the feet are already lifted, and a feet-relative probe
    ## would scan above the step, lose it, and drop the bot — an oscillation.
    if not (self.model of Bot):
      return
    var dir = Bot(self.model).velocity
    dir.y = 0
    if dir.length < 0.1:
      return
    let
      pos = self.global_transform.origin
      ahead = pos + dir.normalized * 0.6
      probe = vec3(ahead.x, floor_top + 0.45, ahead.z)
    for unit in state.units.value:
      if unit of Build and ?unit.node:
        let
          build = Build(unit)
          bnode = Spatial(unit.node)
          local = bnode.global_transform.xform_inv_vector3(probe)
          cell = vec3(floor(local.x), floor(local.y), floor(local.z))
        if build.solid_at(cell) and not build.solid_at(cell + vec3(0, 1, 0)):
          let top = bnode.global_transform.xform_vector3(
            vec3(local.x, cell.y + 1.0, local.z)
          ).y
          if top > floor_top + 0.05 and top <= floor_top + 1.1:
            return some(top)

  proc ride_and_fall(delta: float) =
    ## Two node-side, world-space (no reparenting) behaviours off one floor
    ## query:
    ## - Ride: carry the bot by the rigid motion (rotation + translation) of the
    ##   surface under its feet, so it rides a moving/turning platform.
    ## - Floor-follow: keep the bot on that surface vertically — step up onto
    ##   blocks, and fall off ledges under a fake gravity matching the player's.
    ## Horizontal (walk + ride) and vertical (this) are independent; the script's
    ## turtle moves own X/Z, this owns Y. Applied after the bot's own walk.
    if LOADING_LEVEL in state.global_flags:
      return
    # Fell out of the world (genuinely bottomless): reset high instead of a
    # runaway free-fall to -inf.
    if self.translation.y < -50:
      var t = self.translation
      t.y = 30
      self.translation = t
      self.fall_velocity = 0.0
      return
    # Look past this frame's fall step: a long fall drops more per frame than a
    # fixed reach, so it would step across a floor between frames (tunnel).
    # When grounded, also look one block up, so a step the bot has walked into
    # (feet embedded) is climbed; never while falling, so dropping past a
    # ledge's edge doesn't yank the bot up onto it.
    let next_fall = self.fall_velocity + state.gravity * delta
    let reach_up = if self.fall_velocity < 0: 0.0 else: 0.99
    let floor_hit = self.find_floor(1.0 - next_fall * delta, reach_up)
    if floor_hit.is_none:
      # Nothing underfoot. Only fall if we've stood on something before — a bot
      # placed in mid-air (or mid level-load) should wait, not drop forever.
      self.floor_prev_id = 0
      if self.floor_seen:
        self.fall_velocity = next_fall
        var t = self.translation
        t.y += self.fall_velocity * delta
        self.translation = t
      return
    self.floor_seen = true
    var target_y = floor_hit.get.top + foot_offset
    if self.fall_velocity >= 0:
      # A single block in the walking path becomes the floor target: the bot
      # lifts onto it while its center is still behind the block's face (the
      # probe keeps seeing the step ahead), and the walk carries it across.
      # Skipped while falling, so dropping past a ledge isn't yanked sideways.
      let step = self.climb_step(floor_hit.get.top)
      if step.is_some and step.get > target_y:
        target_y = step.get
    block:
      var t = self.translation
      if t.y > target_y + 0.01:
        # Airborne above the surface (walked off / stepping down) — fall toward
        # it, landing exactly on it. No ride carry while airborne.
        self.floor_prev_id = 0
        self.fall_velocity = next_fall
        t.y = max(t.y + self.fall_velocity * delta, target_y)
        if t.y == target_y:
          self.fall_velocity = 0.0
        self.translation = t
        return
    self.fall_velocity = 0.0
    let fnode = floor_hit.get.node
    if fnode.is_nil:
      # The ground plane — static, nothing to ride.
      self.floor_prev_id = 0
    else:
      let
        id = fnode.get_instance_id
        now = fnode.global_transform
      # Ride (horizontal + rotation). Skip a static surface: `now * now.inverse`
      # isn't exactly identity in float32, so applying it every frame would
      # drift.
      if id == self.floor_prev_id and now != self.floor_prev_transform:
        let motion = now * self.floor_prev_transform.affine_inverse
        self.global_transform = motion * self.global_transform
      self.floor_prev_id = id
      self.floor_prev_transform = now
    # Settle / step up onto the surface. Rising (climb, step-up) is animated at
    # climb_speed rather than snapped; already-settled stays pinned exactly.
    var t = self.translation
    t.y = min(t.y + climb_speed * delta, target_y)
    self.translation = t

  method process(delta: float) =
    # Render-tick only: the screenshot warm-up counts render frames. Movement and
    # riding moved to physics_process so they share the platform's (and player's)
    # tick — see physics_process.
    self.process_screenshot()

  method physics_process(delta: float) =
    if ?self.model:
      if self.model of Bot:
        let bot = Bot(self.model)
        # Move only while a script is driving the bot, so it stops when the
        # script ends. Riding is independent: a bot rides whatever it stands on
        # whether or not it's running a script.
        if SCRIPT_RUNNING in self.model.global_flags and bot.velocity.length > 0:
          discard self.move_and_slide(self.model.velocity, UP)
        self.ride_and_fall(delta)
      if self.model.code.owner == state.worker_ctx_name:
        self.model.transform_value.pause self.transform_zid:
          self.model.transform = self.transform

var bot_scene {.threadvar.}: PackedScene
proc init*(_: type BotNode): BotNode =
  if bot_scene.is_nil:
    bot_scene = load("res://components/BotNode.tscn") as PackedScene
  result = bot_scene.instance() as BotNode
