import std/[tables, bitops, times, options, sets]
import pkg/godot except print, Color
import
  godotapi/[
    node, voxel_terrain, voxel_mesher_blocky, voxel_tool, voxel_library,
    voxel_buffer, voxel_server, shader_material, resource_loader, packed_scene,
    ray_cast,
  ]
import core, models/[units, builds, colors, voxels], gdutils
import ./queries

const
  highlight_glow = 1.0
  default_glow = 0.0
  error_flash_time = 0.5.seconds

var build_scene {.threadvar.}: PackedScene
var shader {.threadvar.}: Shader
var hidden_shader {.threadvar.}: Shader

gdobj BuildNode of VoxelTerrain:
  var
    model*: Build
    transform_zid: ZID
    default_view_distance: int
    toggle_error_highlight_at = MonoTime.high
    error_highlight_on: bool
    loaded_chunks: HashSet[Vector3]
    tracked_delta_seqs: Table[Vector3, ZID]
    renderer: VoxelRenderer

  proc init*() =
    self.bind_signals self, "block_loaded", "block_unloaded"
    self.default_view_distance = self.max_view_distance.int

  proc prepare_materials() =
    if self.model.shared.materials.len == 0:
      for i in 0 .. int.high:
        let m = self.get_material(i)
        if m.is_nil:
          break
        else:
          let m = m.duplicate.as(ShaderMaterial)
          m.set_shader_param("emission_energy", default_glow.to_variant)
          self.model.shared.emission_colors.add(
            m.get_shader_param("emission").as_color
          )

          self.model.shared.materials.add(m)

    for i, material in self.model.shared.materials:
      self.set_material(i, material)

  proc watch_delta_seq(chunk_id: Vector3, delta_seq: ZenSeq[DeltaUpdate]) =
    if chunk_id in self.tracked_delta_seqs:
      return

    let zid = delta_seq.watch:
      if added:
        self.renderer.render_delta(chunk_id, change.item)

    self.tracked_delta_seqs[chunk_id] = zid

  method on_block_loaded(chunk_id: Vector3) =
    if ?self.model:
      self.loaded_chunks.incl(chunk_id)

  method on_block_unloaded(chunk_id: Vector3) =
    if ?self.model:
      self.loaded_chunks.excl(chunk_id)

  proc set_glow(glow: float) =
    let library = self.mesher.as(VoxelMesherBlocky).library
    for i in 0 ..< library.voxel_count.int:
      let m = self.get_material(i).as(ShaderMaterial)
      if not m.is_nil:
        m.set_shader_param("emission_energy", glow.to_variant)

  proc set_highlight() =
    let library = self.mesher.as(VoxelMesherBlocky).library
    for i in 0 ..< library.voxel_count.int:
      let m = self.get_material(i).as(ShaderMaterial)
      if not m.is_nil:
        if self.error_highlight_on:
          m.set_shader_param("emission", action_colors[Red].to_variant)
        else:
          m.set_shader_param(
            "emission", self.model.shared.emission_colors[i].to_variant
          )

        if Highlight in self.model.local_flags or
            (
              HighlightError in self.model.global_flags and
              self.error_highlight_on
            ):
          m.set_shader_param("emission_energy", highlight_glow.to_variant)
        else:
          m.set_shader_param("emission_energy", self.model.glow.to_variant)

  proc set_visibility() =
    if Visible in self.model.global_flags:
      self.visible = true

      for material in self.model.shared.materials:
        material.shader = shader
    elif Visible notin self.model.global_flags and God in state.local_flags:
      self.visible = true

      for material in self.model.shared.materials:
        material.shader = hidden_shader
    else:
      self.visible = false

  proc track_changes() =
    self.model.glow_value.watch:
      if added:
        self.set_glow(change.item)

    self.bounds = self.model.bounds
    self.model.bounds_value.watch:
      if added:
        debug "changing bounds", new = change.item
        self.bounds = change.item

    # Watch packed_chunks for snapshots - renderer handles rendering
    self.model.voxels.packed_chunks.watch:
      if added:
        self.renderer.render_snapshot(change.item.key, change.item.value)

    # Watch chunk_deltas for incremental updates
    self.model.voxels.chunk_deltas.watch:
      if added:
        let chunk_id = change.item.key
        let delta_seq = change.item.value
        if not delta_seq.isNil:
          # Render any existing deltas
          for delta in delta_seq:
            self.renderer.render_delta(chunk_id, delta)
          # Watch for future deltas
          self.watch_delta_seq(chunk_id, delta_seq)
      elif removed:
        let chunk_id = change.item.key
        if chunk_id in self.tracked_delta_seqs:
          Zen.thread_ctx.untrack(self.tracked_delta_seqs[chunk_id])
          self.tracked_delta_seqs.del(chunk_id)

    self.model.global_flags.watch:
      if (
        change.item == Visible and
        ScriptInitializing notin self.model.global_flags
      ) or ScriptInitializing.removed:
        self.set_visibility
      elif Resetting.added:
        self.loaded_chunks.clear()
        self.generator = nil
        self.stream = nil
      elif Resetting.removed:
        self.generator = gdnew[VoxelGeneratorFlat]()
      elif HighlightError.added:
        self.toggle_error_highlight_at = get_mono_time() + error_flash_time
        self.error_highlight_on = true
        self.set_highlight
      elif HighlightError.removed:
        self.toggle_error_highlight_at = MonoTime.high
        self.error_highlight_on = false
        self.set_highlight

    self.model.local_flags.watch:
      if change.item == Highlight:
        self.set_highlight
      elif change.item == ASAPMode:
        if added:
          self.renderer.begin_asap()
        elif removed:
          self.renderer.end_asap()

    state.local_flags.watch:
      if change.item == God:
        self.set_visibility

    self.model.scale_value.watch:
      if added:
        let scale = change.item
        self.scale = vec3(scale, scale, scale)
        self.model.transform_value.pause self.transform_zid:
          self.model.transform = self.transform
        self.max_view_distance = int(self.default_view_distance.float / scale)

    self.transform_zid = self.model.transform_value.watch:
      if added:
        self.transform = change.item

    self.model.sight_query_value.watch:
      if added:
        var query = change.item
        let collision_layer = self.collision_layer
        self.collision_layer = 0
        query.run(self.model)
        self.collision_layer = collision_layer
        self.model.sight_query = query

  method process(delta: float) =
    if ?self.model:
      if self.model.code.owner == state.worker_ctx_name:
        self.model.transform_value.pause self.transform_zid:
          self.model.transform = self.transform

      if get_mono_time() > self.toggle_error_highlight_at:
        self.error_highlight_on = not self.error_highlight_on
        self.toggle_error_highlight_at = get_mono_time() + error_flash_time
        self.set_highlight()

      # Paste buffered voxels when not in ASAP mode
      if ASAPMode notin self.model.local_flags:
        self.renderer.paste_if_dirty()

  proc setup*() =
    let was_skipping_join = dont_join
    dont_join = true

    self.model.init_voxels_if_needed()

    # Create renderer for direct buffer rendering
    self.renderer = VoxelRenderer.init()
    self.renderer.voxel_tool = self.get_voxel_tool()

    self.track_changes

    dont_join = was_skipping_join
    if not self.model.bot_collisions:
      var layer = 0
      layer.set_bits(2)
      self.collision_layer = layer

    self.model.sight_ray = self.get_node("SightRay") as RayCast
    self.prepare_materials()

proc init*(_: type BuildNode): BuildNode =
  if build_scene.is_nil:
    build_scene = load("res://components/BuildNode.tscn") as PackedScene
    shader = load("res://shaders/terrain_voxel.shader") as Shader
    hidden_shader = load("res://shaders/terrain_voxel_hidden.shader") as Shader
  result = build_scene.instance() as BuildNode
