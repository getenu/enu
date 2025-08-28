import std/[tables, monotimes, times]
import gdext
import gdext/classes/[gdvoxelterrain, gdvoxeltool, gdvoxeltoolterrain, gdvoxelmesher, gdvoxelmesherblocky, 
                     gdvoxelblockylibrary, gdvoxelblockylibrarybase, gdvoxelstream, gdvoxelstreammemory, 
                     gdvoxelgenerator, gdvoxelgeneratorflat, gdvoxelblockymodel,
                     gdvoxelblockymodelcube, gdvoxelblockymodelempty, gdvoxelbuffer]

# BuildNode for Godot 4 using complete custom Godot bindings with voxel support
type BuildNode* {.gdsync.} = ptr object of VoxelTerrain
  test_voxels_created: bool
  creation_time: MonoTime

proc create_test_voxels*(self: BuildNode) {.gdsync.} =
  ## Create some test voxels using real VoxelTerrain functionality
  if self.test_voxels_created:
    return

  print("[VOXEL] Creating test voxels with properly initialized VoxelTerrain...")

  # Get voxel tool for editing
  let voxel_tool = self.get_voxel_tool()

  print("[VOXEL] VoxelTool acquired, creating 3x3x3 cube...")

  # Create a simple 3x3x3 cube of different colored blocks
  for x in 0..2:
    for y in 0..2:
      for z in 0..2:
        let pos = vector3i(x.int32, y.int32, z.int32)
        # Alternate between different voxel types (1-6 for different colors)
        let voxel_type = (x + y + z) mod 6 + 1
        voxel_tool[].set_voxel(pos, voxel_type.uint64)

  print("[VOXEL] Test voxels created - 3x3x3 cube with mixed colors")
  self.test_voxels_created = true

method onInit*(self: BuildNode) =
  # Constructor-like initialization
  self.test_voxels_created = false
  self.creation_time = get_mono_time()

method ready*(self: BuildNode) {.gdsync.} =
  print("[VOXEL] BuildNode ready - setting up VoxelTerrain with complete configuration...")

  # 1. Set up a VoxelStream for data storage
  let voxel_stream = VoxelStreamMemory.instantiate
  self.setStream(voxel_stream.as(gdref VoxelStream))
  print("[VOXEL] VoxelStreamMemory configured for data storage")

  # 2. Set up VoxelGenerator - this is CRITICAL for editability!
  let generator = VoxelGeneratorFlat.instantiate
  generator[].setChannel(VoxelBuffer_ChannelId(1))  # TYPE channel for blocky terrain
  self.setGenerator(generator.as(gdref VoxelGenerator))
  print("[VOXEL] VoxelGeneratorFlat configured with TYPE channel - areas should now be editable!")

  # 3. Set up VoxelBlockyLibrary with models for the mesher
  let library = VoxelBlockyLibrary.instantiate
  
  # Add model 0: Empty/Air block
  let empty_model = VoxelBlockyModelEmpty.instantiate
  discard library[].addModel(empty_model.as(gdref VoxelBlockyModel))
  
  # Add model 1-6: Solid cube blocks for our test voxels
  for i in 1..6:
    let cube_model = VoxelBlockyModelCube.instantiate
    discard library[].addModel(cube_model.as(gdref VoxelBlockyModel))
  
  print("[VOXEL] VoxelBlockyLibrary configured with 7 models (0=air, 1-6=cubes)")

  # 4. Set up VoxelMesherBlocky with the library
  let mesher = VoxelMesherBlocky.instantiate
  mesher[].setLibrary(library.as(gdref VoxelBlockyLibraryBase))
  self.setMesher(mesher.as(gdref VoxelMesher))
  print("[VOXEL] VoxelMesherBlocky configured with library")
  
  print("[VOXEL] VoxelTerrain setup complete - should be fully editable now!")
  # Create test voxels now that everything is properly configured
  self.create_test_voxels()
