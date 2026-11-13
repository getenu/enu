import std/[tables, sets]
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



# 0.2.2's named save points. Remove in 0.4.

var
  save_points: Table[string, Table[string, Pen]]
  warned_about_save: HashSet[string]

proc warn_about_save(self: Build) =
  if self.id notin warned_about_save:
    warned_about_save.incl self.id
    echo "`save` and `restore` are deprecated and will be removed in 0.4. ",
      "Use `var spot = pen` to save and `pen = spot` to restore. ",
      "See https://getenu.com/docs/api/enu_api.html"

proc save*(self: Build, name = "default") {.deprecated: "use `var spot = pen`".} =
  ## Deprecated: use `var spot = pen`.
  self.warn_about_save
  save_points.mget_or_put(self.id, init_table[string, Pen]())[name] = self.pen

proc restore*(self: Build, name = "default") {.deprecated: "use `pen = spot`".} =
  ## Deprecated: use `pen = spot`.
  self.warn_about_save
  self.pen = save_points[self.id][name]

proc save*(name = "default") {.deprecated: "use `var spot = pen`".} =
  Build(active_thing()).save(name)

proc restore*(name = "default") {.deprecated: "use `pen = spot`".} =
  Build(active_thing()).restore(name)
