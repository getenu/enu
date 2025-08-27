import std/[tables, monotimes, times]
import gdext
import ../../../../generated/gdext_custom/gdext/classes/gdvoxelterrain
import ../../../../generated/gdext_custom/gdext/classes/gdvoxeltoolterrain

# BuildNode for Godot 4 using complete custom Godot bindings with voxel support
type BuildNode* {.gdsync.} = ptr object of VoxelTerrain
  test_voxels_created: bool
  creation_time: MonoTime

proc create_test_voxels*(self: BuildNode) {.gdsync.} =
  ## Create some test voxels using real VoxelTerrain functionality
  if self.test_voxels_created:
    return
    
  print("[VOXEL] Creating test voxels with real VoxelTerrain...")
  
  let voxel_tool = self.getVoxelTool()
  if voxel_tool.is_nil():
    print("[VOXEL] ERROR: VoxelTool is nil")
    return
  
  # Create a simple 3x3x3 cube of different colored blocks
  for x in 0..2:
    for y in 0..2:
      for z in 0..2:
        let pos = vector3i(x, y, z)
        # Alternate between different voxel types (1-6 for different colors)
        let voxel_type = (x + y + z) mod 6 + 1
        voxel_tool.setVoxel(pos, voxel_type.int32)
        
  print("[VOXEL] Test voxels created - 3x3x3 cube with mixed colors")
  self.test_voxels_created = true

method onInit*(self: BuildNode) =
  # Constructor-like initialization
  self.test_voxels_created = false
  self.creation_time = get_mono_time()

method ready*(self: BuildNode) {.gdsync.} =
  print("[VOXEL] BuildNode ready - setting up test voxels")
  
  # Note: Not calling super.ready() since VoxelTerrain is a stub type
  
  # Wait a frame to ensure everything is initialized
  # TODO: Use proper signal/timer when gdext supports it  
  self.create_test_voxels()

method process*(self: BuildNode, delta: float) {.gdsync.} =
  # Create voxels after a short delay to ensure VoxelTerrain is fully initialized
  if not self.test_voxels_created and get_mono_time() > self.creation_time + initDuration(seconds = 1):
    self.create_test_voxels()