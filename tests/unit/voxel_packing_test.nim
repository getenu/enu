import unittest2
import core
import models/voxels
import models/colors

suite "Voxel Packing":
  test "pack_voxel for hole (kind=0, color=0) should not return 0":
    # HOLE is kind 0, ERASER is color 0
    let packed = pack_voxel(0, 0)
    check packed == 1 # My fix changed it to 1
    check packed != EMPTY_VOXEL # Should not be 0

  test "unpack_voxel for 1 should return hole":
    let (color_index, kind_ord) = unpack_voxel(1.PackedVoxel)
    check kind_ord == 0 # HOLE
    check color_index == 0 # ERASER

  test "pack_voxel for normal block":
    # kind 1 (MANUAL), color 1 (BLUE)
    let packed = pack_voxel(1, 1)
    check packed > 1

    let (color_index, kind_ord) = unpack_voxel(packed)
    check kind_ord == 1
    check color_index == 1

  test "EMPTY_VOXEL is 0":
    check EMPTY_VOXEL == 0
