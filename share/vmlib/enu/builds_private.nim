import core, builds, vm_bridge_utils

bridged_to_host:
  proc place_block*(self: Build, position: Vector3, color: Color)
    ## Place a persistent PERSISTED voxel. The block is saved to local_edits
    ## and survives reload. Intended for explicit user-style edits (eg.
    ## carving holes for windows, eval-driven edits from MCP). For
    ## programmatic block-placement use draw_voxel / box / place,
    ## which mark voxels TRANSIENT and let the script regenerate them on
    ## reload.

  proc persist*(self: Build)
    ## Promote everything the script has drawn (normally TRANSIENT, dropped and
    ## regenerated each reload) into saved PERSISTED voxels, then mark the build
    ## dirty so they're written to disk. After calling this you can delete the
    ## drawing code and the voxels stay. An authoring tool for baking a build:
    ## draw it, `persist()`, `save_level_now()`, then strip the drawing code.

proc fill_square*(length = 1) =
  Build(active_thing()).fill_square(length)

proc persist*() =
  Build(active_thing()).persist()


