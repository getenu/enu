import types, base_api, builds, vm_bridge_utils

bridged_to_host:
  proc place_block*(self: Build, position: Vector3, color: Colors)
    ## Place a persistent MANUAL voxel. The block is saved to local_edits
    ## and survives reload. Intended for explicit user-style edits (eg.
    ## carving holes for windows, eval-driven edits from MCP). For
    ## programmatic block-placement use draw_voxel / fill_box / place,
    ## which mark voxels COMPUTED and let the script regenerate them on
    ## reload.

proc fill_square*(length = 1) =
  Build(active_unit()).fill_square(length)

proc save*(name = "default") =
  Build(active_unit()).save(name)

proc restore*(name = "default") =
  Build(active_unit()).restore(name)
