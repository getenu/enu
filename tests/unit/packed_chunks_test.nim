import unittest2
import core
import models/[colors, packed_chunks]

suite "Packed Voxel Encoding":
  test "pack/unpack voxel round-trip for all colors and kinds":
    for color_idx in 0 ..< 7:  # 7 defined colors
      for kind_ord in 0 ..< 3:  # 3 voxel kinds
        let packed = pack_voxel(color_idx, kind_ord)
        let (c, k) = unpack_voxel(packed)
        check c == color_idx
        check k == kind_ord

  test "empty voxel encoding":
    let packed = pack_voxel(0, KIND_HOLE)
    check packed == EMPTY_VOXEL
    let (c, k) = unpack_voxel(EMPTY_VOXEL)
    check c == 0
    check k == KIND_HOLE

  test "packed values are within valid range":
    for color_idx in 0 ..< 80:
      for kind_ord in 0 ..< 3:
        let packed = pack_voxel(color_idx, kind_ord)
        check packed <= 240  # Must be below command bytes

suite "Linear Position Encoding":
  test "linear position round-trip for all chunk positions":
    for x in 0 ..< CHUNK_SIZE:
      for y in 0 ..< CHUNK_SIZE:
        for z in 0 ..< CHUNK_SIZE:
          let pos = vec3(x.float, y.float, z.float)
          let linear = linear_position(pos)
          let restored = from_linear(linear)
          check restored == pos

  test "linear position range is 0-4095":
    check linear_position(0, 0, 0) == 0
    check linear_position(15, 15, 15) == 4095
    check linear_position(vec3(0, 0, 0)) == 0
    check linear_position(vec3(15, 15, 15)) == 4095

  test "linear position layout is z + y*16 + x*256":
    check linear_position(1, 0, 0) == 256
    check linear_position(0, 1, 0) == 16
    check linear_position(0, 0, 1) == 1

  test "negative positions use floor modulo":
    # -1 should wrap to 15 (not -1)
    check linear_position(vec3(-1, 0, 0)) == linear_position(vec3(15, 0, 0))
    check linear_position(vec3(0, -1, 0)) == linear_position(vec3(0, 15, 0))
    check linear_position(vec3(0, 0, -1)) == linear_position(vec3(0, 0, 15))
    # -17 should wrap to 15 (-17 mod 16 = 15 with floor mod)
    check linear_position(vec3(-17, 0, 0)) == linear_position(vec3(15, 0, 0))
    # 17 should wrap to 1 (17 mod 16 = 1)
    check linear_position(vec3(17, 0, 0)) == linear_position(vec3(1, 0, 0))

suite "Varint Encoding":
  test "write and read varint round-trip":
    for value in [0'u64, 1, 127, 128, 255, 256, 4095, 10000]:
      var s = ""
      write_varint(s, value)
      var i = 0
      let result = read_varint(s, i)
      check result == value
      check i == s.len

  test "varint encoding uses minimal bytes":
    var s = ""
    write_varint(s, 0)
    check s.len == 1

    s = ""
    write_varint(s, 127)
    check s.len == 1

    s = ""
    write_varint(s, 4095)
    check s.len <= 3  # SQLite varint format may use up to 3 bytes for 4095

suite "RLE Compression":
  test "RLE encode/decode round-trip":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    for i in 0 ..< 100:
      voxels[i] = 5
    for i in 100 ..< 500:
      voxels[i] = 10
    for i in 500 ..< CHUNK_VOLUME:
      voxels[i] = 0

    let encoded = encode_rle_data(voxels)
    let decoded = decode_rle_data(encoded)

    for i in 0 ..< CHUNK_VOLUME:
      check decoded[i] == voxels[i]

  test "RLE compresses uniform chunks efficiently":
    var uniform: array[CHUNK_VOLUME, PackedVoxel]
    for i in 0 ..< CHUNK_VOLUME:
      uniform[i] = 5

    let encoded = encode_rle_data(uniform)
    check encoded.len < 100  # Should be very small

  test "RLE format byte is correct":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    let encoded = encode_rle_data(voxels)
    check encoded[0] == FMT_RLE

suite "PackedChunk Encoding":
  test "encode/decode empty chunk":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    let packed = encode_chunk(voxels)
    check packed.is_empty
    check packed.format_name == "empty"

    let decoded = decode_chunk(packed)
    for i in 0 ..< CHUNK_VOLUME:
      check decoded[i] == EMPTY_VOXEL

  test "encode/decode uniform chunk":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    for i in 0 ..< CHUNK_VOLUME:
      voxels[i] = pack_voxel(1, KIND_MANUAL)

    let packed = encode_chunk(voxels)
    check not packed.is_empty
    check packed.data.len < 100  # Should be very compact

    let decoded = decode_chunk(packed)
    for i in 0 ..< CHUNK_VOLUME:
      check decoded[i] == voxels[i]

  test "encode/decode sparse chunk":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    voxels[0] = pack_voxel(1, KIND_MANUAL)
    voxels[100] = pack_voxel(2, KIND_COMPUTED)
    voxels[4000] = pack_voxel(3, KIND_HOLE)

    let packed = encode_chunk(voxels)
    check not packed.is_empty

    let decoded = decode_chunk(packed)
    for i in 0 ..< CHUNK_VOLUME:
      check decoded[i] == voxels[i]

  test "adaptive encoding picks smaller format":
    # Uniform chunk - RLE should win
    var uniform: array[CHUNK_VOLUME, PackedVoxel]
    for i in 0 ..< CHUNK_VOLUME:
      uniform[i] = pack_voxel(1, KIND_MANUAL)

    let packed_uniform = encode_chunk(uniform, ceAdaptive)
    check packed_uniform.format_name == "RLE"

    # Very sparse chunk - sparse should win
    var sparse: array[CHUNK_VOLUME, PackedVoxel]
    sparse[0] = pack_voxel(1, KIND_MANUAL)

    let packed_sparse = encode_chunk(sparse, ceAdaptive)
    check packed_sparse.format_name == "sparse"

  test "forced encoding modes work":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    voxels[0] = pack_voxel(1, KIND_MANUAL)

    let rle = encode_chunk(voxels, ceRLE)
    check rle.format_name == "RLE"

    let sparse = encode_chunk(voxels, ceSparse)
    check sparse.format_name == "sparse"

    # Both should decode correctly
    let decoded_rle = decode_chunk(rle)
    let decoded_sparse = decode_chunk(sparse)
    for i in 0 ..< CHUNK_VOLUME:
      check decoded_rle[i] == voxels[i]
      check decoded_sparse[i] == voxels[i]
