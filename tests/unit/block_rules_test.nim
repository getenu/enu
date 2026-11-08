import unittest2
import core
import models
import models/builds {.all.}
import models/voxels/[store, codec]

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

proc edit_row(build: Build): EditKey =
  (build.id, 0, chunk_id_for_pos(spot))

suite "Edits changed elsewhere":
  # Rows written straight to the synced edit tables stand in for main's
  # clicks or another player's edits arriving on the worker.

  test "a row changed elsewhere is read again":
    let build = Build.init(id = "build_edits_changed")
    build.manual(red)
    build.voxels.flush_dirty_edits()
    check build.voxels.has_edit(spot)
    build.voxels.edit_snapshots.del(build.edit_row)
    check not build.voxels.has_edit(spot)

  test "a delta added elsewhere is read again":
    let build = Build.init(id = "build_edits_delta")
    build.manual(red)
    build.voxels.flush_dirty_edits()
    build.draw(spot + vec3(1, 0, 0), (PERSISTED, blue))
    build.voxels.flush_dirty_edits()
    check build.edit_row in build.voxels.edit_deltas
    check build.voxels.has_edit(spot)
    build.voxels.edit_deltas[build.edit_row].add encode_delta(
      @[(local_pos_in_chunk(spot), EMPTY_VOXEL)]
    )
    check not build.voxels.has_edit(spot)

  test "unflushed edits survive a re-read":
    let build = Build.init(id = "build_edits_pending")
    build.manual(red)
    build.voxels.edit_row_changed((0, chunk_id_for_pos(spot)))
    check build.voxels.get_edit(spot) == (PERSISTED, red)

  test "a hole made elsewhere is seen by the next run":
    let build = Build.init(id = "build_edits_remote_hole")
    build.manual(red)
    build.voxels.flush_dirty_edits()
    build.unmark_holes() # the chunk is known to have no holes
    var cells: array[CHUNK_VOLUME, PackedVoxel]
    cells[linear_position(spot)] = pack_voxel(ERASER.ord, HOLE.ord)
    build.voxels.edit_snapshots[build.edit_row] = encode_chunk(cells)
    check build.has_hole
    build.unmark_holes()
    build.collect_garbage()
    check not build.voxels.has_edit(spot)

proc run(build: Build) =
  ## What a script run does before its script: as reset() with a script.
  build.start_frames_run(scripted = true)
  build.reset()

suite "Frames":
  let hand = vec3(5, 3, 4)

  test "each frame keeps its own holes and manual blocks":
    let build = Build.init(id = "build_frames_holes")
    build.computed(red)
    build.erase_cell(spot)
    build.draw(hand, (PERSISTED, blue))
    build.go_to_frame(1)
    check build.frames_len == 2
    check spot notin build
    check not build.voxels.has_edit(spot)
    check not build.voxels.has_edit(hand)
    build.computed(red)
    build.go_to_frame(0)
    check build.has_hole
    check spot notin build
    check build.voxels.get_edit(hand) == (PERSISTED, blue)
    build.go_to_frame(1)
    check not build.voxels.has_edit(hand)
    check build.voxel_info(spot) == (TRANSIENT, red)

  test "a script run drops every frame's computed blocks and starts on 0":
    let build = Build.init(id = "build_frames_rerun")
    build.go_to_frame(1)
    build.computed(red)
    build.draw(hand, (PERSISTED, blue))
    build.go_to_frame(2)
    build.computed(red)
    build.run()
    check build.frame == 0
    build.go_to_frame(1)
    check spot notin build
    check build.voxels.get_edit(hand) == (PERSISTED, blue)
    build.go_to_frame(2)
    check spot notin build

  test "a frame's hole stays only while the run draws into it":
    let build = Build.init(id = "build_frames_run_holes")
    for index in 1 .. 2:
      build.go_to_frame(index)
      build.computed(red)
      build.erase_cell(spot)
    build.run()
    build.go_to_frame(1)
    build.computed(red)
    build.go_to_frame(0)
    build.collect_garbage() # the run finishes
    build.go_to_frame(1)
    check build.has_hole
    check spot notin build
    build.go_to_frame(2)
    check not build.has_hole

  test "a run rebuilds a frame only once a script draws into it":
    let build = Build.init(id = "build_frames_restored")
    build.go_to_frame(1)
    build.draw(hand, (PERSISTED, blue))
    build.run()
    build.voxels.with_frame(build.frame_id(1)):
      check not build.voxels.restore_needed
    build.go_to_frame(1)
    build.computed(red)
    check build.voxels.restore_needed
    build.run()
    build.go_to_frame(1)
    check spot notin build
    check build.voxels.get_edit(hand) == (PERSISTED, blue)

  test "copy, insert, delete and paste":
    let build = Build.init(id = "build_frames_ops")
    build.computed(red) # frame 0
    build.copy_frame(0, 2) # frame 1 grows empty
    check build.frames_len == 3
    build.go_to_frame(2)
    check build.voxel_info(spot) == (TRANSIENT, red)
    build.draw(hand, (PERSISTED, blue))
    build.insert_frame(2, 0) # frames move up; the current one with them
    check build.frames_len == 4
    check build.frame == 3
    check build.voxels.get_edit(hand) == (PERSISTED, blue)
    build.delete_frames(1, 2)
    check build.frames_len == 2
    check build.frame == 1
    build.clear_frame(0)
    build.paste_frame(1, 0)
    build.go_to_frame(0)
    check build.voxel_info(spot) == (TRANSIENT, red)
    check build.voxels.get_edit(hand) == (PERSISTED, blue)

  test "clearing frames keeps the current one as frame 0":
    let build = Build.init(id = "build_frames_clear")
    build.go_to_frame(3)
    build.computed(red)
    build.clear_frames()
    check build.frames_len == 1
    check build.frame == 0
    check build.voxel_info(spot) == (TRANSIENT, red)
