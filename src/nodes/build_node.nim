import std/[tables, bitops]
import pkg/godot except print, Color
import
  godotapi/[
    node, voxel_terrain, voxel_mesher_blocky, voxel_tool, voxel_library,
    shader_material, resource_loader, packed_scene, ray_cast
  ]
import core, models/[units, builds, colors], globals
import ./queries

const
  highlight_glow = 1.0
  default_glow = 0.0
  empty_zid: ZID = 0
  error_flash_time = 0.5.seconds

var build_scene {.threadvar.}: PackedScene
var shader {.threadvar.}: Shader
var hidden_shader {.threadvar.}: Shader

gdobj BuildNode of VoxelTerrain:
  var
    model*: Build
    active_chunks: Table[Vector3, ZID]
    transform_zid: ZID
    default_view_distance: int
    chunks_zid: ZID
    toggle_error_highlight_at = MonoTime.high
    error_highlight_on: bool

  proc init*() =
    self.bind_signals self, "block_loaded", "block_unloaded"
    self.default_view_distance = self.max_view_distance.int

  proc prepare_materials() =
    if self.model.shared.materials.len == 0:
      # generate our own copy of the library materials, so we can manipulate
      # them without impacting other builds.
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

  proc draw(location: Vector3, color: Color) =
    self.get_voxel_tool.set_voxel(location, ord color.action_index)

  proc draw_block(voxels: Chunk) =
    for loc, info in voxels:
      self.draw(loc, info.color)

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
          m.set_shader_param("emission", action_colors[red].to_variant)
        else:
          m.set_shader_param(
            "emission", self.model.shared.emission_colors[i].to_variant
          )

        if Highlight in self.model.local_flags or (
          HighlightError in self.model.local_flags and self.error_highlight_on
        ):
          m.set_shader_param("emission_energy", highlight_glow.to_variant)
        else:
          m.set_shader_param("emission_energy", self.model.glow.to_variant)

  proc track_chunk(chunk_id: Vector3) =
    if chunk_id in self.model.chunks:
      self.draw_block(self.model.chunks[chunk_id])
      self.active_chunks[chunk_id] =
        self.model.chunks[chunk_id].watch:
          # `and not modified` isn't required, but the block will be
          # replaced on the next iteration anyway.
          if removed and not modified:
            self.draw(change.item.key, action_colors[eraser])
          elif added:
            self.draw(change.item.key, change.item.value.color)
      self.draw_block(self.model.chunks[chunk_id])
    else:
      self.active_chunks[chunk_id] = empty_zid

  method on_block_loaded(chunk_id: Vector3) =
    if ?self.model:
      self.track_chunk(chunk_id)

  method on_block_unloaded(chunk_id: Vector3) =
    if ?self.model:
      let zid = self.active_chunks[chunk_id]
      if zid != empty_zid:
        self.model.chunks[chunk_id].untrack(zid)
      self.active_chunks.del(chunk_id)

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

  proc track_chunks() =
    self.chunks_zid =
      self.model.chunks.watch:
        let id = change.item.key
        if id in self.active_chunks:
          if added:
            self.track_chunk(change.item.key)
          elif removed:
            self.active_chunks[id] = empty_zid

  proc untrack_chunks() =
    Zen.thread_ctx.untrack(self.chunks_zid)
    for chunk_id, zid in self.active_chunks:
      Zen.thread_ctx.untrack(zid)
      self.active_chunks[chunk_id] = empty_zid

  proc track_changes() =
    self.model.glow_value.watch:
      if added:
        self.set_glow(change.item)

    self.bounds = self.model.bounds
    self.model.bounds_value.watch:
      if added:
        debug "changing bounds", new = change.item
        self.bounds = change.item

    self.track_chunks()

    self.model.global_flags.watch:
      if (
        change.item == Visible and
        ScriptInitializing notin self.model.global_flags
      ) or ScriptInitializing.removed:
        self.set_visibility
      elif Resetting.added:
        self.untrack_chunks()
        let model = self.model
        self.generator = nil
        self.stream = nil
      elif Resetting.removed:
        self.generator = gdnew[VoxelGeneratorFlat]()
        self.track_chunks()

    self.model.local_flags.watch:
      if HighlightError.added:
        self.toggle_error_highlight_at = get_mono_time() + error_flash_time
        self.error_highlight_on = true
      elif HighlightError.removed:
        self.toggle_error_highlight_at = MonoTime.high
        self.error_highlight_on = false
      if change.item in [Highlight, HighlightError]:
        self.set_highlight

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

    self.transform_zid =
      self.model.transform_value.watch:
        if added:
          self.transform = change.item

    self.model.sight_query_value.watch:
      if added:
        var query = change.item
        # disable collisions during query so ray doesn't collide with us.
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

  proc setup*() =
    let was_skipping_join = dont_join
    dont_join = true

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
