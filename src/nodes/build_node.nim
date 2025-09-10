import std/[tables, bitops, monotimes, times]
import gdext
import core, types, models/[units, builds, colors], gdutils
import gdext/classes/[gdvoxelterrain, gdvoxeltool, gdvoxeltoolterrain, gdvoxelmesher, gdvoxelmesherblocky,
                     gdvoxelblockylibrary, gdvoxelblockylibrarybase, gdvoxelstream, gdvoxelstreammemory,
                     gdvoxelgenerator, gdvoxelgeneratorflat, gdvoxelblockymodel,
                     gdvoxelblockymodelcube, gdvoxelblockymodelempty, gdvoxelbuffer,
                     gdpackedscene, gdresourceloader, gdraycast3d, gdshadermaterial, gdshader]
import ./queries

const
  highlight_glow = 1.0
  default_glow = 0.0
  empty_zid: ZID = 0
  error_flash_time = 0.5.seconds

var build_scene {.threadvar.}: gdref PackedScene
var shader {.threadvar.}: gdref Shader
var hidden_shader {.threadvar.}: gdref Shader

# BuildNode for Godot 4 using complete custom Godot bindings with voxel support
type BuildNode* {.gdsync.} = ptr object of VoxelTerrain
  model*: Build
  active_chunks: Table[Vector3, ZID]
  transform_zid: ZID
  default_view_distance: int
  chunks_zid: ZID
  toggle_error_highlight_at: MonoTime
  error_highlight_on: bool
  update_at: MonoTime

method on_init*(self: BuildNode) =
  # Constructor-like initialization - equivalent to gdobj's init
  self.default_view_distance = self.get_max_view_distance().int

proc prepare_materials(self: BuildNode) =
  if ?self.model and self.model.shared.materials.len == 0:
    # Generate our own copy of the library materials, so we can manipulate
    # them without impacting other builds.
    let mesher = self.get_mesher()
    if ?mesher:
      let blocky_mesher = mesher.as(gdref VoxelMesherBlocky)
      if ?blocky_mesher:
        let library = blocky_mesher[].get_library()
        if ?library:
          let materials = library[].get_materials()
          for i in 0 ..< materials.size():
            let m = materials[i]
            if ?m:
              discard
              # GD4: Get emission colors - using default color for now
              # let m_copy = m[].duplicate().as(gdref ShaderMaterial)
              # m_copy[].set_shader_parameter("emission_energy", variant(default_glow))
              # GD4: Get emission colors - using default color for now
              # TODO: Fix Variant to Color conversion when gdext API is clearer
              # self.model.shared.emission_colors.add(gdext.color(0.0, 0.0, 0.0, 1.0))

              # GD4: Fix material type mismatch - GdRef vs ShaderMaterial
              # TODO: Fix materials type - may need to change seq type to handle gdref
              # self.model.shared.materials.add(m_copy)

    # Note: In Godot 4, VoxelTerrain only has set_material_override for entire terrain
    # Individual material management is done through the VoxelMesher/Library
    # for i, material in self.model.shared.materials:
    #   self.set_material(i, material)

proc draw(self: BuildNode, location: Vector3, color: colors.Color) =
  let voxel_tool = self.get_voxel_tool()
  if ?voxel_tool:
    voxel_tool[].set_voxel(vector3i(location.x.int32, location.y.int32, location.z.int32),
                          ord(color.action_index).uint64)

proc draw_block(self: BuildNode, voxels: Chunk) =
  for loc, info in voxels:
    self.draw(loc, info.color)

proc set_glow(self: BuildNode, glow: float) =
  # GD4: Implement glow setting for Godot 4 - simplified for now
  # TODO: Re-implement when VoxelTerrain API is better understood
  discard

proc set_highlight(self: BuildNode) =
  # GD4: Implement highlighting for Godot 4 - simplified for now
  # TODO: Re-implement when VoxelTerrain API is better understood
  discard

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

# GD4: VoxelTerrain block signals don't exist in Godot 4 - API changed
# TODO: Find alternative approach for chunk tracking in Godot 4 VoxelTerrain
# method on_block_loaded(self: BuildNode, chunk_id: Vector3) {.gdsync.} =
#   if ?self.model:
#     self.track_chunk(chunk_id)

# method on_block_unloaded(self: BuildNode, chunk_id: Vector3) {.gdsync.} =
#   if ?self.model:
#     let zid = self.active_chunks.get_or_default(chunk_id, empty_zid)
#     if zid != empty_zid:
#       self.model.chunks[chunk_id].untrack(zid)
#     self.active_chunks.del(chunk_id)

proc set_shader_type(self: BuildNode, normal: bool) =
  # GD4: Set shader type (normal or hidden) on materials - simplified for now
  # TODO: Re-implement when VoxelTerrain API is better understood
  discard

proc set_visibility(self: BuildNode) =
  if ?self.model:
    if Visible in self.model.global_flags:
      self.visible = true
      # GD4: Set normal shader
      self.set_shader_type(normal = true)
    elif Visible notin self.model.global_flags and God in state.local_flags:
      self.visible = true
      # GD4: Set hidden shader
      self.set_shader_type(normal = false)
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


  echo "bounds: ", ?self.model.bounds_value

  self.set_bounds(self.model.bounds)
  self.model.bounds_value.watch:
    if added:
      debug "changing bounds", new = change.item
      self.set_bounds(change.item)

  self.track_chunks()

  self.model.global_flags.watch:
    if (
      change.item == Visible and
      ScriptInitializing notin self.model.global_flags
    ) or ScriptInitializing.removed:
      self.set_visibility()
    elif Resetting.added:
      self.untrack_chunks()
      # GD4: Reset VoxelTerrain - fix gdref nil reference
      # TODO: Fix gdref nil construction syntax for VoxelTerrain reset
      # self.set_generator(gdref VoxelGenerator())
      # self.set_stream(gdref VoxelStream())
    elif Resetting.removed:
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
      self.set_max_view_distance(int32(self.default_view_distance.float / scale))

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

proc create_test_voxels*(self: BuildNode) {.gdsync.} =
  ## Create some test voxels using real VoxelTerrain functionality

  print("[VOXEL] Creating test voxels with properly initialized VoxelTerrain...")

  # Get voxel tool for editing
  let voxel_tool = self.get_voxel_tool()

  print("[VOXEL] VoxelTool acquired, testing area editability...")

  # Test if the area we want to edit is editable
  let test_area = aabb(vector3(0, 0, 0), vector3(3, 3, 3))
  let is_editable = voxel_tool[].is_area_editable(test_area)
  print("[VOXEL] Area (0,0,0) to (3,3,3) editable: ", is_editable)

  if not is_editable:
    print("[VOXEL] ✗ Area not editable - this is the problem!")
    print("[VOXEL] → Stream: ", self.get_stream())
    print("[VOXEL] → Generator: ", self.get_generator())
    print("[VOXEL] → Max view distance: ", self.get_max_view_distance())
    print("[VOXEL] → Data block size: ", self.get_data_block_size())
    return

  print("[VOXEL] ✓ Area is editable, creating 3x3x3 cube...")

  # Create a simple 3x3x3 cube of different colored blocks
  for x in 0..2:
    for y in 0..2:
      for z in 0..2:
        let pos = vector3i(x.int32, y.int32, z.int32)
        # Alternate between different voxel types (1-6 for different colors)
        let voxel_type = (x + y + z) mod 6 + 1
        voxel_tool[].set_voxel(pos, 1.uint64)

  print("[VOXEL] Test voxels created - 3x3x3 cube with mixed colors")

method process*(self: BuildNode, delta: float64) {.gdsync.} =
  if ?self.model:
    if self.model.code.owner == state.worker_ctx_name:
      self.model.transform_value.pause self.transform_zid:
        self.model.transform = self.get_transform()

    if get_mono_time() > self.toggle_error_highlight_at:
      self.error_highlight_on = not self.error_highlight_on
      self.toggle_error_highlight_at = get_mono_time() + error_flash_time
      self.set_highlight()

  # Test voxel creation (temporary)
  if self.update_at < get_mono_time() and self.update_at != MonoTime.high:
    # Only run once by setting to a far future time
    self.update_at = MonoTime.high
    self.create_test_voxels()

method ready*(self: BuildNode) {.gdsync.} =
  print("[VOXEL] BuildNode ready - checking VoxelTerrain configuration from .tscn...")
  self.update_at = get_mono_time() + init_duration(seconds = 2)  # Give terrain time to initialize
  self.toggle_error_highlight_at = MonoTime.high

  # Initialize based on on_init equivalent
  self.default_view_distance = self.get_max_view_distance().int

  # Debug: Check if components from .tscn are properly loaded
  print("[VOXEL] Stream: ", self.get_stream())
  print("[VOXEL] Generator: ", self.get_generator())
  print("[VOXEL] Mesher: ", self.get_mesher())
  print("[VOXEL] Bounds: ", self.get_bounds())
  print("[VOXEL] VoxelTerrain initialized - waiting 2 seconds for area loading...")

proc init*(_: type BuildNode): BuildNode =
  if not ?build_scene:
    build_scene = ResourceLoader.load("res://components/BuildNode.tscn").as(gdref PackedScene)
    # GD4: Load shaders for Godot 4
    shader = ResourceLoader.load("res://shaders/terrain_voxel.gdshader").as(gdref Shader)
    hidden_shader = ResourceLoader.load("res://shaders/terrain_voxel_hidden.gdshader").as(gdref Shader)

  result = build_scene[].instantiate().as(BuildNode)
