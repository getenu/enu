import std/[tables, math, os]
import pkg/godot except print
import pkg/[chroma]
import
  godotapi/[
    scene_tree, kinematic_body, material, mesh_instance, spatial, input_event,
    animation_player, resource_loader, packed_scene, spatial_material,
    text_edit, camera, viewport, texture, image,
  ]
import gdutils, core, models/[colors, units], ui/markdown_label
import ./queries

gdobj BotNode of KinematicBody:
  var
    model*: Unit
    material* {.gdExport.},
      highlight_material* {.gdExport.},
      selected_material* {.gdExport.}: Material
    skin: Spatial
    mesh: MeshInstance
    animation_player: AnimationPlayer
    transform_zid: EID
    # MCP screenshot is multi-phase: positioning the camera doesn't take
    # effect until the next render, and a projection-mode change (ortho ↔
    # perspective) needs an extra frame on top of that. -1 = idle, N > 0 =
    # warming up (decrement each frame), 0 = capture this frame.
    screenshot_warmup_frames: int = -1
    # Bot hides its own skin during capture so it doesn't fill its own POV
    # when the camera sits near the bot's body (screenshot, screenshot_at).
    skin_hidden_during_screenshot: bool

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

      if self.model of Bot:
        if SCRIPT_RUNNING.added:
          self.set_process(true)
        elif SCRIPT_RUNNING.removed:
          self.set_process(false)

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
        if added:
          let editor = self.get_node("SignNode/Viewport/TextEdit") as TextEdit
          editor.cursor_set_line(change.item.line, true)
          editor.cursor_set_column(change.item.col, true)

    self.model.scale_value.watch:
      if added:
        let scale = change.item
        self.scale = vec3(scale, scale, scale)
        self.model.transform_value.pause(self.transform_zid):
          self.model.transform = self.transform

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
      let is_ephemeral = EPHEMERAL in bot.global_flags
      if is_ephemeral:
        info "mcp bot node setup",
          id = bot.id, has_mcp_query_value = ?bot.mcp_query_value
      self.set_process(
        SCRIPT_RUNNING in self.model.global_flags or is_ephemeral
      )

  method process(delta: float) =
    if self.model of Bot:
      let bot = Bot(self.model)
      if EPHEMERAL in bot.global_flags:
        let q = bot.mcp_query
        if q.kind == MCP_SCREENSHOT and q.state == MCP_READY and
            self.screenshot_warmup_frames > 0:
          dec self.screenshot_warmup_frames
        elif q.kind == MCP_SCREENSHOT and q.state == MCP_READY and
            self.screenshot_warmup_frames == 0:
          let vp =
            if q.screenshot_with_ui:
              self.get_tree().root
            else:
              Viewport(state.mcp_viewport)
          let img = vp.get_texture.get_data
          img.flip_y
          inc state.screenshot_counter
          let path =
            get_temp_dir() /
            ("enu_screenshot_" & $state.screenshot_counter & ".png")
          discard img.save_png(path)
          info "mcp screenshot captured", path
          self.screenshot_warmup_frames = -1
          if self.skin_hidden_during_screenshot:
            self.skin.visible = true
            self.skin_hidden_during_screenshot = false
          bot.mcp_query =
            McpQuery(kind: MCP_SCREENSHOT, result: path, state: MCP_DONE)
        elif q.state == MCP_READY and q.kind == MCP_SCREENSHOT and
            self.screenshot_warmup_frames < 0:
          # with_ui captures the root viewport (game + GUI overlay) so the
          # camera positioning below has no effect — root is already the
          # composited screen. For without-UI we still drive mcp_camera.
          if not q.screenshot_with_ui:
            # mcp_viewport's `world` reference is captured at game.ready
            # time, but the world changes on level switches. Refresh it
            # each shot so the ortho/perspective camera renders against
            # the current level.
            let vp = Viewport(state.mcp_viewport)
            let main_vp = self.get_tree().root
            if not main_vp.is_nil:
              vp.world = main_vp.find_world()
            let cam = Camera(state.mcp_camera)
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
            info "mcp screenshot positioning camera",
              from_player = q.screenshot_from_player,
              top_down = q.screenshot_top_down,
              origin = cam.global_transform.origin
          # Two warm-up frames: one for the transform write to land, one for
          # a projection-mode change (ortho ↔ perspective) to take effect.
          # A single frame was enough most of the time but a perspective
          # capture immediately after an orthographic one occasionally read
          # back the prior frame's ortho render.
          self.screenshot_warmup_frames = 2

    if ?self.model:
      if self.model.code.owner == state.worker_ctx_name:
        self.model.transform_value.pause self.transform_zid:
          self.model.transform = self.transform
      if self.model of Bot:
        let bot = Bot(self.model)
        if bot.velocity.length > 0:
          discard self.move_and_slide(self.model.velocity, UP)

var bot_scene {.threadvar.}: PackedScene
proc init*(_: type BotNode): BotNode =
  if bot_scene.is_nil:
    bot_scene = load("res://components/BotNode.tscn") as PackedScene
  result = bot_scene.instance() as BotNode
