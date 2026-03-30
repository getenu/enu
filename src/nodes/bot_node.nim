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
    pending_mcp_screenshot: McpQuery

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
        if self.pending_mcp_screenshot.kind != MCP_BLANK:
          let vp = Viewport(state.screenshot_viewport)
          let img = vp.get_texture.get_data
          img.flip_y
          inc state.screenshot_counter
          let path =
            get_temp_dir() /
            ("enu_screenshot_" & $state.screenshot_counter & ".png")
          discard img.save_png(path)
          info "mcp screenshot captured", path
          var pq = self.pending_mcp_screenshot
          pq.result = path
          pq.state = MCP_DONE
          bot.mcp_query = pq
          self.pending_mcp_screenshot = McpQuery()
          if ?state.player and ?state.player.node:
            let player_cam = state.player.node.find_node("Camera") as Camera
            if ?player_cam:
              player_cam.make_current()
        else:
          let q = bot.mcp_query
          if q.state == MCP_READY and q.kind == MCP_SCREENSHOT:
            info "mcp screenshot request received", unit_id = q.unit_id
            let is_player =
              q.unit_id == "" or (
                ?state.player and q.unit_id == state.player.id
              )
            if is_player:
              self.pending_mcp_screenshot = q
            else:
              var found: Unit
              state.units.value.walk_tree proc(u: Unit) =
                if u.id == q.unit_id:
                  found = u
              if found.is_nil or not ?found.node:
                info "mcp screenshot unit not found", unit_id = q.unit_id
                var eq = q
                eq.error = "Unit not found: " & q.unit_id
                eq.state = MCP_DONE
                bot.mcp_query = eq
              else:
                let cam = Camera(state.mcp_camera)
                var t = Spatial(found.node).global_transform
                t.origin += vec3(0, 0.8, 0)
                cam.global_transform = t
                cam.make_current()
                self.pending_mcp_screenshot = q

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
