import std/[tables, bitops, monotimes, times]
import gdext
import core, types, models/[units, builds, colors], gdcore
import
  gdext/classes/[
    gdvoxelterrain, gdvoxeltool, gdvoxeltoolterrain, gdvoxelmesher,
    gdvoxelmesherblocky, gdvoxelblockylibrary, gdvoxelblockylibrarybase,
    gdvoxelstream, gdvoxelstreammemory, gdvoxelgenerator, gdvoxelgeneratorflat,
    gdvoxelblockymodel, gdvoxelblockymodelcube, gdvoxelblockymodelempty,
    gdvoxelbuffer, gdpackedscene, gdresourceloader, gdraycast3d,
    gdshadermaterial, gdmaterial,
  ]
import ./queries

const
  highlight_glow = 1.0
  default_glow = 0.0
  empty_zid: ZID = 0
  error_flash_time = 0.5.seconds

var build_scene {.threadvar.}: gdref PackedScene

# BuildNode for Godot 4 using complete custom Godot bindings with voxel support
type BuildNode* {.gdsync.} =
  ptr object of VoxelTerrain
    model*: Build
    active_chunks: Table[Vector3, ZID]
    transform_zid: ZID
    default_view_distance: int
    chunks_zid: ZID
    toggle_error_highlight_at: MonoTime
    error_highlight_on: bool

proc prepare_materials(self: BuildNode) =
  if ?self.model:
    # Clone the entire mesher and library to get per-build materials
    let mesher = self.get_mesher()
    if ?mesher:
      let mesher_copy = mesher[].duplicate(false).as(gdref VoxelMesherBlocky)
      if ?mesher_copy:
        let library = mesher_copy[].get_library()
        if ?library:
          let blocky_library = library.as(gdref VoxelBlockyLibrary)
          if ?blocky_library:
            let library_copy = blocky_library[].duplicate(false).as(gdref VoxelBlockyLibrary)
            if ?library_copy:
              mesher_copy[].set_library(library_copy.as(gdref VoxelBlockyLibraryBase))

              # Clone materials to get per-build shader materials
              let models = library_copy[].get_models()
              for i in 0 ..< models.size():
                let model = models[i].as(gdref VoxelBlockyModel)
                if ?model:
                  let mat = model[].get_material_override(0)
                  if ?mat:
                    # Clone the material for this build
                    let mat_copy = mat[].duplicate(false).as(gdref ShaderMaterial)
                    if ?mat_copy:
                      # Set default glow
                      mat_copy[].set_shader_parameter("emission_energy".to_string_name(), variant(default_glow))
                      model[].set_material_override(0, mat_copy.as(gdref Material))
                      # Store material reference so we can modify it later
                      self.model.shared.materials.add(mat_copy)

              # Apply the cloned mesher to this BuildNode
              self.set_mesher(mesher_copy.as(gdref VoxelMesher))

proc draw(self: BuildNode, location: Vector3, color: colors.Color) =
  let voxel_tool = self.get_voxel_tool()
  if ?voxel_tool:
    voxel_tool[].set_voxel(
      vector3i(location.x.int32, location.y.int32, location.z.int32),
      ord(color.action_index).uint64,
    )

proc draw_block(self: BuildNode, voxels: Chunk) =
  for loc, info in voxels:
    self.draw(loc, info.color)

proc set_glow(self: BuildNode, glow: float) =
  if ?self.model and self.model.shared.materials.len > 0:
    for i, material in self.model.shared.materials:
      if ?material:
        material[].set_shader_parameter("emission_energy".to_string_name(), variant(glow))

proc set_highlight(self: BuildNode) =
  if ?self.model and self.model.shared.materials.len > 0:
    let glow_value = if Highlight in self.model.local_flags or
        (HighlightError in self.model.global_flags and self.error_highlight_on):
      highlight_glow
    else:
      self.model.glow

    for i, material in self.model.shared.materials:
      if ?material:
        # Set emission color for error highlighting
        if self.error_highlight_on:
          material[].set_shader_parameter("emission".to_string_name(), variant(action_colors[Colors.Red]))
        # Note: We can't easily restore original color since it varies per material
        # For now, error highlighting overrides color. To fully restore, we'd need
        # to store original emission colors per material.

        # Set glow intensity
        material[].set_shader_parameter("emission_energy".to_string_name(), variant(glow_value))

proc track_chunk(self: BuildNode, chunk_id: Vector3) =
  if ?self.model and chunk_id in self.model.chunks:
    self.draw_block(self.model.chunks[chunk_id])
    self.active_chunks[chunk_id] = self.model.chunks[chunk_id].watch:
      # `and not modified` isn't required, but the block will be
      # replaced on the next iteration anyway.
      if removed and not modified:
        self.draw(change.item.key, action_colors[Eraser])
      elif added:
        self.draw(change.item.key, change.item.value.color)
    self.draw_block(self.model.chunks[chunk_id])
  else:
    self.active_chunks[chunk_id] = empty_zid

proc on_block_loaded(self: BuildNode, chunk_id: Vector3i) {.gdsync.} =
  if ?self.model:
    let v3 = vector3(chunk_id.x.float, chunk_id.y.float, chunk_id.z.float)
    self.track_chunk(v3)

proc on_block_unloaded(self: BuildNode, chunk_id: Vector3i) {.gdsync.} =
  if ?self.model:
    let v3 = vector3(chunk_id.x.float, chunk_id.y.float, chunk_id.z.float)
    let zid = self.active_chunks.get_or_default(v3, empty_zid)
    if zid != empty_zid:
      self.model.chunks[v3].untrack(zid)
    self.active_chunks.del(v3)

proc set_visibility(self: BuildNode) =
  if ?self.model:
    if Visible in self.model.global_flags:
      self.visible = true
      # GD4: Shader switching requires per-instance materials
      # For now, just toggle visibility
    elif Visible notin self.model.global_flags and God in state.local_flags:
      self.visible = true
      # GD4: Hidden shader requires per-instance materials
      # For now, just show normally in God mode
    else:
      self.visible = false

proc track_chunks(self: BuildNode) =
  if ?self.model:
    self.chunks_zid = self.model.chunks.watch:
      let id = change.item.key
      if id in self.active_chunks:
        if added:
          self.track_chunk(change.item.key)
        elif removed:
          self.active_chunks[id] = empty_zid

proc untrack_chunks(self: BuildNode) =
  Zen.thread_ctx.untrack(self.chunks_zid)
  for chunk_id, zid in self.active_chunks:
    Zen.thread_ctx.untrack(zid)
    self.active_chunks[chunk_id] = empty_zid

proc track_changes(self: BuildNode) =
  if not ?self.model:
    return

  self.model.glow_value.watch:
    if added:
      self.set_glow(change.item)

  self.set_bounds(self.model.bounds)
  self.model.bounds_value.watch:
    if added:
      debug "changing bounds", new = change.item
      self.set_bounds(change.item)

  self.track_chunks()

  self.model.global_flags.watch:
    if (
      change.item == Visible and ScriptInitializing notin self.model.global_flags
    ) or ScriptInitializing.removed:
      self.set_visibility()
    elif Resetting.added:
      self.untrack_chunks()
      # Clear generator and stream during reset
      self.set_generator(default(gdref VoxelGenerator))
      self.set_stream(default(gdref VoxelStream))
    elif Resetting.removed:
      # Restore generator and stream after reset
      let stream = instantiate(VoxelStreamMemory)
      self.set_stream(stream.as(gdref VoxelStream))
      let generator = instantiate(VoxelGeneratorFlat)
      self.set_generator(generator.as(gdref VoxelGenerator))
      self.track_chunks()
    elif HighlightError.added:
      self.toggle_error_highlight_at = get_mono_time() + error_flash_time
      self.error_highlight_on = true
      self.set_highlight()
    elif HighlightError.removed:
      self.toggle_error_highlight_at = MonoTime.high
      self.error_highlight_on = false
      self.set_highlight()

  self.model.local_flags.watch:
    if change.item == Highlight:
      self.set_highlight()

  state.local_flags.watch:
    if change.item == God:
      self.set_visibility()

  self.model.scale_value.watch:
    if added:
      let scale = change.item
      self.set_scale(vector3(scale, scale, scale))
      self.model.transform_value.pause self.transform_zid:
        self.model.transform = self.get_transform()
      self.set_max_view_distance(
        int32(self.default_view_distance.float / scale)
      )

  self.transform_zid = self.model.transform_value.watch:
    if added:
      self.set_transform(change.item)

  # GD4: Implement sight queries for Godot 4
  self.model.sight_query_value.watch:
    if added:
      var query = change.item
      # Disable collisions during query so ray doesn't collide with us
      let collision_layer = self.get_collision_layer()
      self.set_collision_layer(0)
      query.run(self.model)
      self.set_collision_layer(collision_layer)
      self.model.sight_query = query

proc setup*(self: BuildNode) =
  let was_skipping_join = dont_join
  dont_join = true

  self.track_changes()

  dont_join = was_skipping_join
  if ?self.model and not self.model.bot_collisions:
    var layer = 0'u32
    layer.set_bit(2)
    self.set_collision_layer(layer.int32)

  # GD4: Set up sight ray for Godot 4
  let sight_ray = self.find_child("SightRay", false, false) as RayCast3D
  if ?sight_ray:
    self.model.sight_ray = sight_ray
  self.prepare_materials()

method process*(self: BuildNode, delta: float64) {.gdsync.} =
  if ?self.model:
    if self.model.code.owner == state.worker_ctx_name:
      self.model.transform_value.pause self.transform_zid:
        self.model.transform = self.get_transform()

    if get_mono_time() > self.toggle_error_highlight_at:
      self.error_highlight_on = not self.error_highlight_on
      self.toggle_error_highlight_at = get_mono_time() + error_flash_time
      self.set_highlight()

method ready*(self: BuildNode) {.gdsync.} =
  self.toggle_error_highlight_at = MonoTime.high
  self.default_view_distance = self.get_max_view_distance().int

  # Connect VoxelTerrain signals for chunk loading/unloading
  discard self.connect("block_loaded", self.callable("on_block_loaded"))
  discard self.connect("block_unloaded", self.callable("on_block_unloaded"))

proc init*(_: type BuildNode): BuildNode =
  if not ?build_scene:
    build_scene = ResourceLoader.load("res://components/BuildNode.tscn").as(
        gdref PackedScene
      )

  result = build_scene[].instantiate().as(BuildNode)
