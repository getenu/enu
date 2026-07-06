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

  test "static color indices round-trip":
    let packed = pack_voxel(STATIC_COLOR_BASE + 100, COMPUTED.ord)
    let (color_index, kind_ord) = unpack_voxel(packed)
    check color_index == STATIC_COLOR_BASE + 100
    check kind_ord == COMPUTED.ord

  test "max color index fits uint16":
    let max_index = (65535 - 1) div 3
    let packed = pack_voxel(max_index, COMPUTED.ord)
    check packed == 65535
    let (color_index, kind_ord) = unpack_voxel(packed)
    check color_index == max_index
    check kind_ord == COMPUTED.ord

suite "Chunk codecs":
  proc round_trip(voxels: array[CHUNK_VOLUME, PackedVoxel]) =
    let packed = encode_chunk(voxels)
    check decode_chunk(packed) == voxels

  test "all-named chunks keep the legacy 8-bit formats":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    for i in 0 ..< CHUNK_VOLUME:
      voxels[i] = pack_voxel(int(i mod 7), int(i mod 3))
    let packed = encode_chunk(voxels)
    check packed.data[0].byte in
      [FMT_RLE.byte, FMT_SPARSE_FULL.byte]
    round_trip(voxels)

  test "wide values escalate the chunk to 16-bit formats":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    voxels[0] = pack_voxel(STATIC_COLOR_BASE + 500, COMPUTED.ord) # > 255
    voxels[1] = pack_voxel(1, COMPUTED.ord)
    let packed = encode_chunk(voxels)
    check packed.data[0].byte in
      [FMT_RLE16.byte, FMT_SPARSE_FULL16.byte]
    round_trip(voxels)

  test "values colliding with the RLE escape byte round-trip exactly":
    # Packed values >= CMD_REPEAT (static palette index 80+) fit a byte but
    # collide with the legacy escape code: a short-run literal encoded as
    # `CMD_REPEAT, 0, value` decodes as a run of 3, smearing the rest of the
    # chunk (the sea-demo edge corruption). Such chunks must not pick FMT_RLE.
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    for i in 0 ..< 64:
      # dense wave-like rows so RLE beats sparse, with escape-range values
      # in runs shorter than 3
      voxels[i * 3] =
        pack_voxel(STATIC_COLOR_BASE + 16 + (i mod 4), COMPUTED.ord)
      voxels[i * 3 + 1] = voxels[i * 3]
    check voxels[0] >= CMD_REPEAT.PackedVoxel
    let packed = encode_chunk(voxels)
    check packed.data[0].byte != FMT_RLE.byte
    round_trip(voxels)

  test "alternating wide values round-trip (dither pattern)":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    for i in 0 ..< CHUNK_VOLUME:
      voxels[i] = pack_voxel(
        STATIC_COLOR_BASE + 200 + (i mod 2) * 300, COMPUTED.ord
      )
    round_trip(voxels)

  test "solid wide chunk round-trips via RLE16":
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    for i in 0 ..< CHUNK_VOLUME:
      voxels[i] = pack_voxel(STATIC_COLOR_BASE + 1000, MANUAL.ord)
    let packed = encode_chunk(voxels)
    check packed.data[0].byte == FMT_RLE16.byte
    round_trip(voxels)

  test "legacy CMD_REPEAT stream still decodes":
    # 5x value 7, then literals 3, 9 — hand-built old-format RLE
    var data = ""
    for b in [FMT_RLE.byte, 241'u8, 2'u8, 7'u8, 3'u8, 9'u8]:
      data.add char(b)
    let voxels = decode_chunk(SnapshotData(data: data))
    for i in 0 ..< 5:
      check voxels[i] == 7.PackedVoxel
    check voxels[5] == 3.PackedVoxel
    check voxels[6] == 9.PackedVoxel

  test "delta round-trips, narrow and wide":
    let narrow = @[
      (pos: vec3(1, 2, 3), voxel: pack_voxel(2, COMPUTED.ord)),
      (pos: vec3(4, 5, 6), voxel: EMPTY_VOXEL),
    ]
    let narrow_delta = encode_delta(narrow)
    check narrow_delta.data[0].byte == FMT_SPARSE_DELTA.byte
    check decode_delta(narrow_delta) == narrow

    let wide = @[
      (pos: vec3(1, 2, 3), voxel: pack_voxel(STATIC_COLOR_BASE + 999, 2)),
      (pos: vec3(7, 8, 9), voxel: pack_voxel(1, MANUAL.ord)),
    ]
    let wide_delta = encode_delta(wide)
    check wide_delta.data[0].byte == FMT_SPARSE_DELTA16.byte
    check decode_delta(wide_delta) == wide

suite "Static color palette":
  setup:
    let shared = Shared(palette: EdSeq[Color].init())

  test "named colors pack to their ordinals":
    for c in Colors:
      check pack_color_index(shared, ACTION_COLORS[c]) == c.ord
      check resolve_color(shared, c.ord) == ACTION_COLORS[c]

  test "static colors allocate slots and resolve back":
    let c1 = col"123456"
    let c2 = col"abcdef"
    let i1 = pack_color_index(shared, c1)
    let i2 = pack_color_index(shared, c2)
    check i1 == STATIC_COLOR_BASE
    check i2 == STATIC_COLOR_BASE + 1
    check pack_color_index(shared, c1) == i1 # dedup, no new slot
    check shared.palette.len == 2
    check resolve_color(shared, i1) == c1
    check resolve_color(shared, i2) == c2

  test "alpha normalizes to opaque before allocation":
    var c = col"336699"
    c.a = 0.5
    let idx = pack_color_index(shared, c)
    check resolve_color(shared, idx).a == 1.0

  test "nil shared falls back to legacy quantization":
    check pack_color_index(nil, col"123456") == ERASER.ord
    check pack_color_index(nil, ACTION_COLORS[GREEN]) == GREEN.ord

  test "unknown palette index resolves to visible fallback":
    check resolve_color(shared, STATIC_COLOR_BASE + 99) == ACTION_COLORS[WHITE]

suite "Frame pack/load round-trip":
  test "pack_frame captures every chunk; apply_snapshot restores it":
    let a = VoxelStore.init(unit_id = "frame_a")
    a.add_voxel(vec3(0, 0, 0), (COMPUTED, ACTION_COLORS[BLUE]))
    a.add_voxel(vec3(1, 2, 3), (COMPUTED, ACTION_COLORS[RED]))
    a.add_voxel(vec3(20, 0, -5), (MANUAL, ACTION_COLORS[GREEN])) # 2nd chunk
    a.add_voxel(vec3(4, 4, 4), (HOLE, ACTION_COLORS[ERASER]))

    let frame = a.pack_frame
    check frame.chunks.len == 2

    let b = VoxelStore.init(unit_id = "frame_b")
    for chunk_id, packed in frame.chunks:
      b.apply_snapshot(chunk_id, packed)

    for pos in [vec3(0, 0, 0), vec3(1, 2, 3), vec3(20, 0, -5), vec3(4, 4, 4)]:
      check pos in b
      check b.voxel_info(pos) == a.voxel_info(pos)
    # apply_snapshot doesn't count HOLEs as blocks (add_voxel does — a
    # pre-existing inconsistency for fresh holes); 3 solid + 1 hole here
    check b.block_count == 3
