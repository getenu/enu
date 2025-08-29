import std/[tables, monotimes, times]
import gdext
import types
import gdext/classes/[gdvoxelterrain, gdvoxeltool, gdvoxeltoolterrain, gdvoxelmesher, gdvoxelmesherblocky,
                     gdvoxelblockylibrary, gdvoxelblockylibrarybase, gdvoxelstream, gdvoxelstreammemory,
                     gdvoxelgenerator, gdvoxelgeneratorflat, gdvoxelblockymodel,
                     gdvoxelblockymodelcube, gdvoxelblockymodelempty, gdvoxelbuffer, 
                     gdpackedscene, gdresourceloader]

# BuildNode for Godot 4 using complete custom Godot bindings with voxel support
type BuildNode* {.gdsync.} = ptr object of VoxelTerrain
  model*: Build
  update_at: MonoTime

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

method process*(self: BuildNode, delta: float) {.gdsync.} =
  if self.update_at < get_mono_time():
    # Only run once by setting to a far future time
    self.update_at = get_mono_time() + init_duration(seconds = 3600)
    self.create_test_voxels()


method ready*(self: BuildNode) {.gdsync.} =
  print("[VOXEL] BuildNode ready - checking VoxelTerrain configuration from .tscn...")
  self.update_at = get_mono_time() + init_duration(seconds = 2)  # Give terrain time to initialize

  # Debug: Check if components from .tscn are properly loaded
  print("[VOXEL] Stream: ", self.get_stream())
  print("[VOXEL] Generator: ", self.get_generator())
  print("[VOXEL] Mesher: ", self.get_mesher())
  print("[VOXEL] Bounds: ", self.get_bounds())
  print("[VOXEL] VoxelTerrain initialized - waiting 2 seconds for area loading...")

proc init*(_: type BuildNode): BuildNode =
  let scene = cast[gdref PackedScene](ResourceLoader.load("res://components/Build.tscn"))
  result = BuildNode(scene[].instantiate)
