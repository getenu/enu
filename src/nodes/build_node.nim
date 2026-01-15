import std/[tables, bitops, times]
import pkg/godot except print, Color
import
  godotapi/[
    node, voxel_terrain, voxel_mesher_blocky, voxel_tool, voxel_library,
    voxel_buffer, voxel_server, shader_material, resource_loader, packed_scene,
    ray_cast,
  ]
import core, models/[units, builds, colors], gdutils
import ./queries

const
  highlight_glow = 1.0
  default_glow = 0.0
  empty_zid: ZID = 0
  error_flash_time = 0.5.seconds
  use_bulk_paste = true # Toggle between bulk paste (true) and per-voxel (false)

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
    bulk_paste_done: bool # Skip individual draws after bulk paste

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

  proc draw_all_chunks_per_voxel() =
    ## Draw all chunks using individual set_voxel calls (old approach).
    for chunk_id, chunk in self.model.voxels.chunks:
      self.draw_block(chunk)

  proc draw_all_chunks_bulk() =
    ## Draw all chunks at once using a single large buffer paste.
    ## This triggers only ONE post_edit_area for the entire structure,
    ## avoiding cascading neighbor remeshes at internal chunk boundaries.
    var min_pos = vec3(float.high, float.high, float.high)
    var max_pos = vec3(float.low, float.low, float.low)
    var has_voxels = false

    for chunk_id, chunk in self.model.voxels.chunks:
      for world_pos, info in chunk:
        has_voxels = true
        min_pos.x = min(min_pos.x, world_pos.x)
        min_pos.y = min(min_pos.y, world_pos.y)
        min_pos.z = min(min_pos.z, world_pos.z)
        max_pos.x = max(max_pos.x, world_pos.x)
        max_pos.y = max(max_pos.y, world_pos.y)
        max_pos.z = max(max_pos.z, world_pos.z)

    if not has_voxels:
      return

    let size_x = int(max_pos.x - min_pos.x) + 1
    let size_y = int(max_pos.y - min_pos.y) + 1
    let size_z = int(max_pos.z - min_pos.z) + 1

    # Check VoxelBuffer size limits
    if size_x > MAX_BUILD_DIMENSION or size_y > MAX_BUILD_DIMENSION or
        size_z > MAX_BUILD_DIMENSION:
      error "Build exceeds maximum dimension",
        size_x = size_x,
        size_y = size_y,
        size_z = size_z,
        max = MAX_BUILD_DIMENSION
      return

    let buffer = gdnew[VoxelBuffer]()
    buffer.create(size_x, size_y, size_z)
    buffer.fill(0)

    for chunk_id, chunk in self.model.voxels.chunks:
      for world_pos, info in chunk:
        let local_x = int(world_pos.x - min_pos.x)
        let local_y = int(world_pos.y - min_pos.y)
        let local_z = int(world_pos.z - min_pos.z)
        buffer.set_voxel(ord info.color.action_index, local_x, local_y, local_z)

    self.get_voxel_tool.paste(min_pos, buffer, 1, 0)
    self.bulk_paste_done = true

  proc draw_all_chunks() =
    ## Draw all chunks, logging stats before/after for comparison.
    var voxel_count = 0
    for chunk_id, chunk in self.model.voxels.chunks:
      voxel_count += chunk.len

    let stats_before = self.getStatistics()
    let server_before = getStats()
    let start_time = get_mono_time()

    if use_bulk_paste:
      self.draw_all_chunks_bulk()
    else:
      self.draw_all_chunks_per_voxel()

    let elapsed = get_mono_time() - start_time
    let stats_after = self.getStatistics()
    let server_after = getStats()

    let tasks_before = server_before["tasks"].as_dictionary
    let tasks_after = server_after["tasks"].as_dictionary

    info "draw_all_chunks",
      mode = (if use_bulk_paste: "bulk_paste" else: "per_voxel"),
      voxels = voxel_count,
      elapsed_ms = elapsed.in_milliseconds,
      updated_blocks_before = stats_before["updated_blocks"].as_int,
      updated_blocks_after = stats_after["updated_blocks"].as_int,
      meshing_tasks_before = tasks_before["meshing"].as_int,
      meshing_tasks_after = tasks_after["meshing"].as_int

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

  proc track_chunk(chunk_id: Vector3) =
    if chunk_id in self.model.voxels.chunks:
      let in_asap_mode = ASAPMode in self.model.local_flags
      # Skip initial draw if bulk paste already drew everything, or if in ASAP mode
      if not in_asap_mode and not self.bulk_paste_done:
        self.draw_block(self.model.voxels.chunks[chunk_id])
      self.active_chunks[chunk_id] = self.model.voxels.chunks[chunk_id].watch:
        # Skip drawing during ASAP mode - will be flushed when mode ends
        if ASAPMode notin self.model.local_flags:
          # `and not modified` isn't required, but the block will be
          # replaced on the next iteration anyway.
          if removed and not modified:
            self.draw(change.item.key, action_colors[Eraser])
          elif added:
            self.draw(change.item.key, change.item.value.color)
    else:
      self.active_chunks[chunk_id] = empty_zid

  method on_block_loaded(chunk_id: Vector3) =
    if ?self.model:
      self.track_chunk(chunk_id)

  method on_block_unloaded(chunk_id: Vector3) =
    if ?self.model:
      let zid = self.active_chunks[chunk_id]
      if zid != empty_zid:
        self.model.voxels.chunks[chunk_id].untrack(zid)
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
    self.chunks_zid = self.model.voxels.chunks.watch:
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
      elif change.item == ASAPMode and removed:
        # ASAP mode ended - draw all voxels
        self.draw_all_chunks()

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

    # Initialize voxels if nil (happens when Build is synced between threads
    # before main_thread_joined runs)
    self.model.init_voxels_if_needed()

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
