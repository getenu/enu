import core, builds, vm_bridge_utils

bridged_to_host:
  proc place_block*(self: Build, position: Vector3, color: Color)
    ## Place a persistent PERSISTED voxel. The block is saved to local_edits
    ## and survives reload. Intended for explicit user-style edits (eg.
    ## carving holes for windows, eval-driven edits from MCP). For
    ## programmatic block-placement use draw_voxel / box / place,
    ## which mark voxels TRANSIENT and let the script regenerate them on
    ## reload.

  proc asap_mode*(self: Build): bool
    ## Whether the build is in ASAP mode. For tests.

  proc initializing*(self: Build): bool
    ## Whether the build is still hidden while its script starts. For tests.

  proc persist*(self: Build)
    ## Turn everything the script has drawn into hand-placed blocks and save
    ## them. Use it once, right before you delete the code that drew them: the
    ## blocks stay, but the script can no longer regenerate them cleanly. To
    ## avoid redrawing something slow on every run, use `bake:` instead.

proc fill_square*(length = 1) =
  Build(active_thing()).fill_square(length)

proc persist*() =
  Build(active_thing()).persist()


