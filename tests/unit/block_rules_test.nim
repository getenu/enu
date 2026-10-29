import unittest2
import core
import models
import models/builds {.all.}
import models/voxels/store

# Computed blocks are drawn by a build's script (TRANSIENT); manual ones are
# placed by hand (PERSISTED). Erasing a computed block leaves a HOLE.

# these builds share no world; don't try to join manual blocks across them
dont_join = true

let
  red = ACTION_COLORS[RED]
  blue = ACTION_COLORS[BLUE]
  spot = vec3(2, 3, 4)

proc computed(build: Build, color: Color) =
  build.draw(spot, (TRANSIENT, color))

proc manual(build: Build, color: Color) =
  build.draw(spot, (PERSISTED, color))

proc has_hole(build: Build): bool =
  build.voxels.has_edit(spot) and build.voxels.get_edit(spot).kind == HOLE

suite "Computed and manual blocks":
  test "a manual block wins over a computed one":
    let build = Build.init(id = "build_rules_manual_wins")
    build.manual(red)
    build.computed(blue)
    check build.voxels.has_edit(spot)
    check build.voxel_info(spot).color == red

  test "a computed block the same color as a manual one takes over":
    let build = Build.init(id = "build_rules_same_color")
    build.manual(red)
    build.computed(red)
    check not build.voxels.has_edit(spot)
    check build.voxel_info(spot) == (TRANSIENT, red)

  test "erasing a manual block leaves no hole":
    let build = Build.init(id = "build_rules_erase_manual")
    build.manual(red)
    build.erase_cell(spot)
    check not build.voxels.has_edit(spot)
    check spot notin build

  test "erasing a computed block leaves a hole":
    let build = Build.init(id = "build_rules_erase_computed")
    build.computed(red)
    build.erase_cell(spot)
    check build.has_hole
    check spot notin build

  test "a hole stays while the script keeps drawing into it":
    let build = Build.init(id = "build_rules_hole_kept")
    build.computed(red)
    build.erase_cell(spot)
    build.unmark_holes() # the next run starts
    build.computed(blue) # and draws there again
    build.collect_garbage() # and finishes
    check build.has_hole
    check spot notin build

  test "a hole the script no longer draws into is dropped":
    let build = Build.init(id = "build_rules_hole_dropped")
    build.computed(red)
    build.erase_cell(spot)
    build.unmark_holes()
    build.collect_garbage()
    check not build.voxels.has_edit(spot)
