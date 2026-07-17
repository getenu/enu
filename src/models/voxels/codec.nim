## Stateless voxel serialization: voxel packing, chunk geometry, byte helpers,
## the RLE/sparse chunk codecs, the chunk / delta / frame / edits file formats,
## and static-colour palette resolution. No VoxelStore or rendering state — pure
## functions over bytes and voxels.
import std/[varints, options, math, tables, hashes]
import pkg/godot except print, Color
import core
import models/colors

type ChunkFormat* {.size: sizeof(uint8).} = enum
  FMT_RLE = 0x00 # legacy 8-bit, decode-only
  FMT_SPARSE_FULL = 0x01 # legacy 8-bit, decode-only
  FMT_SPARSE_DELTA = 0x02 # legacy 8-bit, decode-only
  FMT_EMPTY = 0x03
  FMT_RLE16 = 0x04
  FMT_SPARSE_FULL16 = 0x05
  FMT_SPARSE_DELTA16 = 0x06

const CMD_REPEAT* = 241'u8 # legacy 8-bit RLE escape (decoder only)

proc pack_voxel*(color_index: int, kind_ord: int): PackedVoxel =
  ((color_index * 3) + kind_ord + 1).PackedVoxel

proc unpack_voxel*(
    packed: PackedVoxel
): tuple[color_index: int, kind_ord: int] =
  if packed == EMPTY_VOXEL:
    (0, 0)
  else:
    let val = packed.int - 1
    (val div 3, val mod 3)

var palette_warned {.threadvar.}: bool

proc rebuild_palette_cache(shared: Shared) =
  shared.palette_cache.clear
  var i = 0
  for color in shared.palette:
    shared.palette_cache[color] = i
    inc i

proc pack_color_index*(shared: Shared, color: Color): int =
  ## A color's packed index. Named colors keep their `Colors` ordinal — they
  ## stay distinguishable from static RGB so environments can remap them
  ## later. Anything else allocates a slot in the Shared's static palette.
  let named = color.action_index
  if named != ERASER or color == ACTION_COLORS[ERASER]:
    return named.ord

  var color = color
  color.a = 1.0 # a non-eraser color must not pack invisibly
  let renamed = color.action_index
  if renamed != ERASER:
    return renamed.ord

  if shared.is_nil:
    # bare stores (tests) have no palette; keep the legacy quantization
    return ERASER.ord

  # `<` not `!=`: nearest-color snaps add extra cache entries beyond the
  # palette itself, and must survive until a genuinely new sync arrives.
  if shared.palette_cache.len < shared.palette.len:
    shared.rebuild_palette_cache
  if color in shared.palette_cache:
    return STATIC_COLOR_BASE + shared.palette_cache[color]

  if shared.palette.len >= MAX_STATIC_COLORS:
    var best = 0
    var best_dist = float32.high
    var i = 0
    for existing in shared.palette:
      let d = color.distance(existing)
      if d < best_dist:
        best_dist = d
        best = i
      inc i
    if not palette_warned:
      palette_warned = true
      warn "static color palette full; snapping to nearest existing color"
    # cache the snap so a repeated color costs one lookup, not a scan
    shared.palette_cache[color] = best
    return STATIC_COLOR_BASE + best

  let idx = shared.palette.len
  shared.palette.add color
  shared.palette_cache[color] = idx
  STATIC_COLOR_BASE + idx

proc resolve_color*(shared: Shared, color_index: int): Color =
  ## Reverse of `pack_color_index`: named ordinal or static palette lookup.
  if color_index < STATIC_COLOR_BASE:
    if color_index <= ACTION_COLORS.high.ord:
      return ACTION_COLORS[Colors(color_index)]
    return ACTION_COLORS[WHITE] # reserved named range we don't know yet
  let idx = color_index - STATIC_COLOR_BASE
  if not shared.is_nil and idx < shared.palette.len:
    return shared.palette[idx]
  # palette entry hasn't synced (or bare store) — visible fallback
  ACTION_COLORS[WHITE]

proc linear_position*(x, y, z: int): int {.inline.} =
  z + y * ChunkDim + x * ChunkDim * ChunkDim

proc floor_mod*(a, b: int): int {.inline.} =
  result = a mod b
  if result < 0:
    result += b

proc linear_position*(pos: Vector3): int {.inline.} =
  let x = floor_mod(pos.x.int, ChunkDim)
  let y = floor_mod(pos.y.int, ChunkDim)
  let z = floor_mod(pos.z.int, ChunkDim)
  linear_position(x, y, z)

proc from_linear*(idx: int): Vector3 {.inline.} =
  let x = idx div (ChunkDim * ChunkDim)
  let y = (idx div ChunkDim) mod ChunkDim
  let z = idx mod ChunkDim
  vec3(x.float, y.float, z.float)

proc buffer*(position: Vector3): Vector3 =
  (position / ChunkSize).floor

proc chunk_id_for_pos*(position: Vector3): Vector3 =
  vec3(
    math.floor(position.x / ChunkDim).int.float,
    math.floor(position.y / ChunkDim).int.float,
    math.floor(position.z / ChunkDim).int.float,
  )

proc local_pos_in_chunk*(position: Vector3): Vector3 =
  let chunk_id = chunk_id_for_pos(position)
  vec3(
    position.x - chunk_id.x * ChunkDim,
    position.y - chunk_id.y * ChunkDim,
    position.z - chunk_id.z * ChunkDim,
  )

proc write_varint*(s: var string, value: uint64) =
  var buf: array[max_var_int_len, byte]
  let len = write_vu64(buf, value)
  for i in 0 ..< len:
    s.add char(buf[i])

proc read_varint*(s: string, i: var int): uint64 =
  var buf: array[max_var_int_len, byte]
  let available = min(max_var_int_len, s.len - i)
  for j in 0 ..< available:
    buf[j] = s[i + j].uint8
  let bytes_read = read_vu64(buf, result)
  i += bytes_read

proc to_string(data: seq[byte]): string =
  result = new_string(data.len)
  if data.len > 0:
    copyMem(addr result[0], unsafeAddr data[0], data.len)

proc to_bytes(s: string): seq[byte] =
  result = new_seq[byte](s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

proc write_varint(s: var seq[byte], value: uint64) =
  var buf: array[max_var_int_len, byte]
  let len = write_vu64(buf, value)
  for i in 0 ..< len:
    s.add buf[i]

proc read_varint(data: openArray[byte], i: var int): uint64 =
  var buf: array[max_var_int_len, byte]
  let available = min(max_var_int_len, data.len - i)
  for j in 0 ..< available:
    buf[j] = data[i + j]
  i += read_vu64(buf, result)

proc add_u16(s: var seq[byte], v: PackedVoxel) =
  s.add byte(v and 0xff)
  s.add byte(v shr 8)

proc read_u16(data: openArray[byte], i: var int): PackedVoxel =
  result = PackedVoxel(data[i].uint16 or (data[i + 1].uint16 shl 8))
  i += 2

proc add_i32(s: var string, v: int) =
  let u = cast[uint32](int32(v))
  s.add char(u and 0xff)
  s.add char((u shr 8) and 0xff)
  s.add char((u shr 16) and 0xff)
  s.add char((u shr 24) and 0xff)

proc read_i32(s: string, i: var int): int =
  let u =
    uint32(s[i].byte) or (uint32(s[i + 1].byte) shl 8) or
    (uint32(s[i + 2].byte) shl 16) or (uint32(s[i + 3].byte) shl 24)
  i += 4
  int(cast[int32](u))

{.push checks: off.}
# Per-voxel hot loops: dev builds ship without -d:release, and runtime
# checks cost 5-15x here (a 250m sea's frame keys measured 400ms with
# checks, ~25ms without). The decoders carry manual bounds guards.

proc fits_8bit(voxels: array[CHUNK_VOLUME, PackedVoxel]): bool =
  for v in voxels:
    if v > 255:
      return false
  true

proc fits_rle8(voxels: array[CHUNK_VOLUME, PackedVoxel]): bool =
  ## The legacy RLE reserves byte values from CMD_REPEAT up as escape codes,
  ## so it can only carry values strictly below it — a literal >= CMD_REPEAT
  ## has no encoding (the escape token always means a run of >= 3).
  for v in voxels:
    if v >= CMD_REPEAT:
      return false
  true

proc encode_rle8_data(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
  ## Legacy FMT_RLE: 1 byte per voxel with the CMD_REPEAT escape. Only valid
  ## when every value is below CMD_REPEAT; old builds can decode it.
  result = @[FMT_RLE.byte]
  var i = 0
  while i < CHUNK_VOLUME:
    let current = voxels[i]
    var run_length = 1
    while i + run_length < CHUNK_VOLUME and voxels[i + run_length] == current and
        run_length < 258:
      inc run_length

    if run_length >= 3:
      result.add CMD_REPEAT
      result.add (run_length - 3).uint8
      result.add current.uint8
      i += run_length
    else:
      for _ in 0 ..< run_length:
        result.add current.uint8
        inc i

proc encode_rle16_data(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
  ## FMT_RLE16: `[tag u8][count varint][payload]` tokens — tag 1 repeats one
  ## u16 value `count` times, tag 0 is a literal run of `count` u16 values.
  ## No escape byte, so alternating (dithered) chunks stay ~2 B/voxel.
  result = @[FMT_RLE16.byte]
  var i = 0
  while i < CHUNK_VOLUME:
    var run = 1
    while i + run < CHUNK_VOLUME and voxels[i + run] == voxels[i]:
      inc run
    if run >= 3:
      result.add 1'u8
      result.write_varint run.uint64
      result.add_u16 voxels[i]
      i += run
    else:
      # literal run: everything up to the start of the next >= 3 repeat
      let start = i
      var j = i
      while j < CHUNK_VOLUME:
        var r = 1
        while j + r < CHUNK_VOLUME and voxels[j + r] == voxels[j]:
          inc r
        if r >= 3:
          break
        j += r
      result.add 0'u8
      result.write_varint (j - start).uint64
      for k in start ..< j:
        result.add_u16 voxels[k]
      i = j

proc encode_rle_data*(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
  ## Chunks whose values all fit below the escape byte (pure named colors,
  ## and the first ~60 static palette entries) keep the legacy 1-byte format
  ## — identical wire size to before, decodable by old builds. Wider values
  ## escalate the chunk to FMT_RLE16.
  if fits_rle8(voxels):
    encode_rle8_data(voxels)
  else:
    encode_rle16_data(voxels)

proc decode_rle_data*(
    data: openArray[byte], start: int = 1
): array[CHUNK_VOLUME, PackedVoxel] =
  ## Legacy 8-bit FMT_RLE decoder (CMD_REPEAT escape).
  var out_idx = 0
  var i = start
  while i < data.len and out_idx < CHUNK_VOLUME:
    let b = data[i]
    if b == CMD_REPEAT:
      let count = data[i + 1].int + 3
      let value = data[i + 2].PackedVoxel
      for _ in 0 ..< count:
        if out_idx < CHUNK_VOLUME:
          result[out_idx] = value
          inc out_idx
      i += 3
    else:
      result[out_idx] = b.PackedVoxel
      inc out_idx
      inc i

proc decode_rle16_data*(
    data: openArray[byte], start: int = 1
): array[CHUNK_VOLUME, PackedVoxel] =
  var out_idx = 0
  var i = start
  while i < data.len and out_idx < CHUNK_VOLUME:
    let tag = data[i]
    inc i
    let count = read_varint(data, i).int
    if tag == 1'u8:
      if i + 1 >= data.len:
        break
      let value = read_u16(data, i)
      for _ in 0 ..< count:
        if out_idx < CHUNK_VOLUME:
          result[out_idx] = value
          inc out_idx
    else:
      for _ in 0 ..< count:
        if i + 1 >= data.len or out_idx >= CHUNK_VOLUME:
          break
        result[out_idx] = read_u16(data, i)
        inc out_idx

proc encode_sparse_data*(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
  let wide = not fits_8bit(voxels)
  result = @[if wide: FMT_SPARSE_FULL16.byte else: FMT_SPARSE_FULL.byte]
  var count = 0
  for v in voxels:
    if v != EMPTY_VOXEL:
      inc count
  result.write_varint count.uint64

  for i, v in voxels:
    if v != EMPTY_VOXEL:
      result.write_varint i.uint64
      if wide:
        result.add_u16 v
      else:
        result.add v.uint8

proc decode_sparse_data*(
    data: openArray[byte], start: int = 1, wide = false
): array[CHUNK_VOLUME, PackedVoxel] =
  ## Sparse decoder: `wide` selects u16 values (0x05/0x06) over the legacy
  ## single-byte values (0x01/0x02).
  var i = start
  let count = read_varint(data, i).int

  for _ in 0 ..< count:
    let pos = read_varint(data, i)
    if wide:
      if i + 1 >= data.len:
        break
      let voxel = read_u16(data, i)
      if pos < CHUNK_VOLUME.uint64:
        result[pos.int] = voxel
    else:
      if i >= data.len:
        break
      let voxel = data[i].PackedVoxel
      inc i
      if pos < CHUNK_VOLUME.uint64:
        result[pos.int] = voxel

{.pop.}

proc encode_chunk*(voxels: array[CHUNK_VOLUME, PackedVoxel]): PackedChunk =
  var has_voxels = false
  for v in voxels:
    if v != EMPTY_VOXEL:
      has_voxels = true
      break

  if not has_voxels:
    return PackedChunk(data: $char(FMT_EMPTY.byte))

  let rle = encode_rle_data(voxels)
  let sparse = encode_sparse_data(voxels)
  if rle.len <= sparse.len:
    PackedChunk(data: rle.to_string)
  else:
    PackedChunk(data: sparse.to_string)

{.push checks: off.}
proc decode_chunk*(packed: PackedChunk): array[CHUNK_VOLUME, PackedVoxel] =
  if packed.data.len == 0:
    return

  let format = ChunkFormat(packed.data[0].byte)
  case format
  of FMT_RLE:
    result = decode_rle_data(packed.data.to_bytes, 1)
  of FMT_SPARSE_FULL, FMT_SPARSE_DELTA:
    result = decode_sparse_data(packed.data.to_bytes, 1)
  of FMT_RLE16:
    result = decode_rle16_data(packed.data.to_bytes, 1)
  of FMT_SPARSE_FULL16, FMT_SPARSE_DELTA16:
    result = decode_sparse_data(packed.data.to_bytes, 1, wide = true)
  of FMT_EMPTY:
    discard

{.pop.}

proc is_empty*(packed: PackedChunk): bool =
  packed.data.len == 0 or
    (packed.data.len == 1 and packed.data[0].byte == FMT_EMPTY.byte)

proc renders_as_air*(packed: PackedVoxel): bool {.inline.} =
  ## A cell that contributes no geometry: true air, or a HOLE. `eraser`
  ## records a HOLE (not true emptiness) so it can subtract from a base
  ## layer, but a hole must always render as nothing — never a solid block.
  ## Frame snapshots captured after an eraser draw carry HOLEs; without this
  ## they'd paint the erased cells as solid voxels (see fill_chunk_type_bytes).
  if packed == EMPTY_VOXEL:
    return true
  let (_, kind_ord) = unpack_voxel(packed)
  VoxelKind(kind_ord) == HOLE

proc voxel_count*(packed: PackedChunk): int =
  ## Non-empty cells in an encoded chunk — what painting this content
  ## would report as painted (see render_snapshot_direct).
  if packed.is_empty:
    return 0
  for voxel in decode_chunk(packed):
    if not voxel.renders_as_air:
      inc result

proc encode_delta*(
    changes: openArray[tuple[pos: Vector3, voxel: PackedVoxel]]
): DeltaUpdate =
  var wide = false
  for (_, voxel) in changes:
    if voxel > 255:
      wide = true
      break

  var bytes: seq[byte] =
    @[if wide: FMT_SPARSE_DELTA16.byte else: FMT_SPARSE_DELTA.byte]
  bytes.write_varint changes.len.uint64

  for (pos, voxel) in changes:
    bytes.write_varint linear_position(pos).uint64
    if wide:
      bytes.add_u16 voxel
    else:
      bytes.add voxel.uint8
  result.data = bytes.to_string

const
  EDITS_FILE_VERSION* = 1'u8
  EDITS_SIDECAR_THRESHOLD* = 1000
    ## Units with more edited voxels than this persist their edits as a
    ## packed-chunk sidecar (data/<id>/edits.bin, ~30-40x smaller) instead
    ## of the per-voxel JSON list (~50KB at the threshold). Small builds
    ## keep the readable, diffable JSON.

proc encode_edits_file*(
    edits: Table[string, Table[Vector3, SnapshotData]]
): string =
  ## A unit tree's hand edits as packed chunks, keyed by unit id — the
  ## same content the JSON "edits" object carries, minus the per-voxel
  ## expansion. Static colors reference the palette saved in the unit JSON.
  result.add char(EDITS_FILE_VERSION)
  result.add_i32 edits.len
  for thing_id, chunks in edits:
    result.add_i32 thing_id.len
    result.add thing_id
    result.add_i32 chunks.len
    for chunk_id, snapshot in chunks:
      result.add_i32 chunk_id.x.int
      result.add_i32 chunk_id.y.int
      result.add_i32 chunk_id.z.int
      result.add_i32 snapshot.data.len
      result.add snapshot.data

proc decode_edits_file*(
    data: string
): Table[string, Table[Vector3, SnapshotData]] =
  if data.len < 5 or data[0].uint8 != EDITS_FILE_VERSION:
    raise ValueError.init("unsupported edits file")
  var i = 1
  let unit_count = read_i32(data, i)
  for _ in 0 ..< unit_count:
    let id_len = read_i32(data, i)
    let thing_id = data[i ..< i + id_len]
    i += id_len
    let chunk_count = read_i32(data, i)
    var chunks: Table[Vector3, SnapshotData]
    for _ in 0 ..< chunk_count:
      let x = read_i32(data, i)
      let y = read_i32(data, i)
      let z = read_i32(data, i)
      let len = read_i32(data, i)
      chunks[vec3(x.float, y.float, z.float)] =
        SnapshotData(data: data[i ..< i + len])
      i += len
    result[thing_id] = chunks

proc pack_and_store_edited_voxels*(
    shared: Shared, id: string, edits: openArray[(Vector3, VoxelInfo)]
) =
  ## Takes a list of world-space edits, groups them by chunk,
  ## packs them, and stores in shared.edit_snapshots.
  var chunks: Table[Vector3, array[CHUNK_VOLUME, PackedVoxel]]

  for (world_pos, info) in edits:
    let chunk_id = chunk_id_for_pos(world_pos)
    let local_pos = local_pos_in_chunk(world_pos)
    let linear = linear_position(local_pos)

    if linear >= 0 and linear < CHUNK_VOLUME:
      if chunk_id notin chunks:
        var empty_chunk: array[CHUNK_VOLUME, PackedVoxel]
        chunks[chunk_id] = empty_chunk

      chunks[chunk_id][linear] =
        pack_voxel(pack_color_index(shared, info.color), info.kind.ord)

  for chunk_id, voxels in chunks:
    let packed = encode_chunk(voxels)
    if not packed.is_empty:
      let key: EditKey = (id, chunk_id)
      shared.edit_snapshots[key] = packed

proc decode_delta*(
    delta: DeltaUpdate
): seq[tuple[pos: Vector3, voxel: PackedVoxel]] =
  if delta.data.len == 0:
    return @[]
  let format = delta.data[0].byte
  let wide = format == FMT_SPARSE_DELTA16.byte
  if not wide and format != FMT_SPARSE_DELTA.byte:
    return @[]

  let data = delta.data.to_bytes
  var i = 1
  let count = read_varint(data, i).int

  for _ in 0 ..< count:
    let linear = read_varint(data, i)
    let voxel =
      if wide:
        if i + 1 >= data.len:
          break
        read_u16(data, i)
      else:
        if i >= data.len:
          break
        let v = data[i].PackedVoxel
        inc i
        v
    result.add (from_linear(linear.int), voxel)

const
  FRAME_FILE_VERSION* = 1'u8
  FRAME_KEYFRAME_INTERVAL* = 8
    ## Every Kth sidecar frame file is a full snapshot; the rest are
    ## per-chunk deltas against the previous frame (5-10x smaller on the
    ## animated-sea workload).

type FrameEntryKind {.size: sizeof(uint8).} = enum
  ENTRY_SNAPSHOT
  ENTRY_DELTA
  ENTRY_REMOVED

proc encode_frame_file*(
    frame: FrameData, prev: Option[FrameData]
): string =
  ## One animation frame as a persistence sidecar file. With no `prev` the
  ## file is a keyframe (every chunk, full snapshots); otherwise each chunk
  ## is stored as nothing (unchanged), a sparse delta, or a snapshot —
  ## whichever is smaller — plus tombstones for chunks the frame dropped.
  result.add char(FRAME_FILE_VERSION)
  result.add char(if prev.is_some: 1'u8 else: 0'u8)
  var entries: seq[tuple[chunk_id: Vector3, kind: FrameEntryKind, data: string]]
  if prev.is_none:
    for chunk_id, snapshot in frame.chunks:
      entries.add (chunk_id, ENTRY_SNAPSHOT, snapshot.data)
  else:
    let prev = prev.get
    for chunk_id, snapshot in frame.chunks:
      if chunk_id in prev.chunks:
        if prev.chunks[chunk_id].data == snapshot.data:
          continue
        let before = decode_chunk(prev.chunks[chunk_id])
        let after = decode_chunk(snapshot)
        var changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]]
        for linear in 0 ..< CHUNK_VOLUME:
          if before[linear] != after[linear]:
            changes.add (from_linear(linear), after[linear])
        let delta = encode_delta(changes)
        if delta.data.len < snapshot.data.len:
          entries.add (chunk_id, ENTRY_DELTA, delta.data)
        else:
          entries.add (chunk_id, ENTRY_SNAPSHOT, snapshot.data)
      else:
        entries.add (chunk_id, ENTRY_SNAPSHOT, snapshot.data)
    for chunk_id in prev.chunks.keys:
      if chunk_id notin frame.chunks:
        entries.add (chunk_id, ENTRY_REMOVED, "")
  result.add_i32 entries.len
  for (chunk_id, kind, data) in entries:
    result.add_i32 chunk_id.x.int
    result.add_i32 chunk_id.y.int
    result.add_i32 chunk_id.z.int
    result.add char(kind.uint8)
    result.add_i32 data.len
    result.add data

proc decode_frame_file*(
    data: string, prev: Option[FrameData]
): FrameData =
  ## Inverse of encode_frame_file. A delta file starts from `prev` and
  ## applies its entries; a keyframe stands alone.
  if data.len < 6 or data[0].uint8 != FRAME_FILE_VERSION:
    raise ValueError.init("unsupported frame file")
  let is_delta = data[1].byte == 1
  if is_delta:
    if prev.is_none:
      raise ValueError.init("delta frame file without a previous frame")
    result.chunks = prev.get.chunks
  var i = 2
  let count = read_i32(data, i)
  for _ in 0 ..< count:
    let x = read_i32(data, i)
    let y = read_i32(data, i)
    let z = read_i32(data, i)
    let chunk_id = vec3(x.float, y.float, z.float)
    let kind = FrameEntryKind(data[i].uint8)
    inc i
    let len = read_i32(data, i)
    let payload = data[i ..< i + len]
    i += len
    case kind
    of ENTRY_SNAPSHOT:
      result.chunks[chunk_id] = SnapshotData(data: payload)
    of ENTRY_DELTA:
      var voxels =
        if chunk_id in result.chunks:
          decode_chunk(result.chunks[chunk_id])
        else:
          default(array[CHUNK_VOLUME, PackedVoxel])
      for (pos, voxel) in decode_delta(DeltaUpdate(data: payload)):
        voxels[linear_position(pos)] = voxel
      result.chunks[chunk_id] = encode_chunk(voxels)
    of ENTRY_REMOVED:
      result.chunks.del(chunk_id)

