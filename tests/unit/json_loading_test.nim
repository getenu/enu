import unittest2
import std/[json, tables, options]
import core
import models/voxels
import models/colors
import models/serializers {.all.} # import private procs like from_json_hook

# Mock Shared object since we don't have full game state
type MockShared = ref object
  edit_snapshots: EdTable[EditKey, SnapshotData]
  edit_deltas: EdTable[EditKey, EdSeq[DeltaUpdate]]

suite "JSON Loading of Holes":
  setup:
    let shared = Shared(
      edit_snapshots: EdTable[EditKey, SnapshotData].init(),
      edit_deltas: EdTable[EditKey, EdSeq[DeltaUpdate]].init(),
    )

  test "loading [0, \"\"] from JSON results in persisted hole":
    let json_str =
      """
      [
        [[-17.0, 5.0, 135.0], [0, ""]]
      ]
    """
    let json = parse_json(json_str)

    # 1. Simulate loading edits from JSON
    var edits: seq[(Vector3, VoxelInfo)] = @[]
    for edit in json:
      let pos_node = edit[0]
      let world_pos = vec3(
        pos_node[0].get_float, pos_node[1].get_float, pos_node[2].get_float
      )

      let info_node = edit[1]
      let kind = VoxelKind(info_node[0].get_int)
      let color_str = info_node[1].get_str
      let color =
        if color_str == "":
          ACTION_COLORS[ERASER]
        else:
          ACTION_COLORS[BLACK] # Simplify for test

      # VoxelInfo is a tuple
      let info: VoxelInfo = (kind: kind, color: color)
      edits.add((world_pos, info))

    check edits.len == 1
    check edits[0][1].kind == HOLE
    check edits[0][1].color == ACTION_COLORS[ERASER] # "" -> ERASER

    # 2. Pack and store
    pack_and_store_edited_voxels(shared, "test_build", edits)

    # 3. Verify snapshot exists
    let chunk_id = chunk_id_for_pos(edits[0][0])
    var found = false
    for k, v in shared.edit_snapshots:
      if k.id == "test_build" and k.loc == chunk_id:
        found = true
        break
    check found

    # 4. Initialize VoxelStore and rebuild edits
    var voxels = VoxelStore.init(
      id = "test_voxels",
      unit_id = "test_build",
      edit_snapshots = shared.edit_snapshots,
    )
    voxels.rebuild_local_edits()

    # 5. Verify hole exists in VoxelStore
    let pos = edits[0][0]
    check voxels.has_edit(pos)
    let edit = voxels.get_edit(pos)
    check edit.kind == HOLE
    check edit.color == ACTION_COLORS[ERASER]
