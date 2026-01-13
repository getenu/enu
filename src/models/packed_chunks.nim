import std/[varints]
import pkg/core/godotcoretypes except Color
import pkg/core/vector3

const
  CHUNK_SIZE* = 16
  CHUNK_VOLUME* = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE  # 4096

  # Format bytes (first byte of packed data)
  FMT_RLE* = 0x00'u8          # Full chunk, RLE encoded
  FMT_SPARSE_FULL* = 0x01'u8  # Full chunk, sparse encoding (position + voxel pairs)
  FMT_SPARSE_DELTA* = 0x02'u8 # Delta update (for future use)
  FMT_EMPTY* = 0x03'u8        # Empty chunk (no voxels)

  # Command bytes for RLE (241+)
  CMD_REPEAT* = 241'u8

  # Empty voxel value
  EMPTY_VOXEL* = 0'u8

  # VoxelKind values (matching types.nim)
  KIND_HOLE* = 0
  KIND_MANUAL* = 1
  KIND_COMPUTED* = 2

type
  PackedVoxel* = uint8

  SnapshotData* = object
    ## Encoded snapshot data for a chunk.
    ## First byte indicates format, rest is format-specific data.
    data*: string

  DeltaUpdate* = object
    ## A delta update containing only changed voxels.
    ## Sparse format: count + (position, voxel) pairs
    data*: string

  # Legacy type alias for compatibility
  PackedChunk* = SnapshotData

proc pack_voxel*(color_index: int, kind_ord: int): PackedVoxel =
  ## Pack color index and kind ordinal into a single byte.
  ## Returns 0 for empty, 1-240 for valid voxels.
  if color_index == 0 and kind_ord == KIND_HOLE:
    result = EMPTY_VOXEL
  else:
    result = ((color_index * 3) + kind_ord + 1).PackedVoxel

proc unpack_voxel*(packed: PackedVoxel): tuple[color_index: int, kind_ord: int] =
  ## Unpack a byte into color index and kind ordinal.
  if packed == EMPTY_VOXEL:
    result = (0, KIND_HOLE)
  else:
    let val = packed.int - 1
    result.color_index = val div 3
    result.kind_ord = val mod 3

proc linear_position*(x, y, z: int): int {.inline.} =
  ## Convert 3D chunk-local position to linear index (0-4095).
  ## Layout: z + y*16 + x*256
  z + y * CHUNK_SIZE + x * CHUNK_SIZE * CHUNK_SIZE

proc floor_mod(a, b: int): int {.inline.} =
  ## Euclidean modulo that always returns a non-negative result.
  ## -1 floorMod 16 = 15, not -1
  result = a mod b
  if result < 0:
    result += b

proc linear_position*(pos: Vector3): int {.inline.} =
  ## Convert Vector3 chunk-local position to linear index.
  ## Handles negative positions correctly using floor modulo.
  let x = floor_mod(pos.x.int, CHUNK_SIZE)
  let y = floor_mod(pos.y.int, CHUNK_SIZE)
  let z = floor_mod(pos.z.int, CHUNK_SIZE)
  linear_position(x, y, z)

proc from_linear*(idx: int): Vector3 {.inline.} =
  ## Convert linear index back to 3D position within chunk.
  let x = idx div (CHUNK_SIZE * CHUNK_SIZE)
  let y = (idx div CHUNK_SIZE) mod CHUNK_SIZE
  let z = idx mod CHUNK_SIZE
  vec3(x.float, y.float, z.float)

proc write_varint*(s: var string, value: uint64) =
  ## Write a varint to a string.
  var buf: array[maxVarIntLen, byte]
  let len = writeVu64(buf, value)
  for i in 0 ..< len:
    s.add char(buf[i])

proc read_varint*(s: string, i: var int): uint64 =
  ## Read a varint from a string at position i, advancing i.
  var buf: array[maxVarIntLen, byte]
  let available = min(maxVarIntLen, s.len - i)
  for j in 0 ..< available:
    buf[j] = s[i + j].uint8
  let bytes_read = readVu64(buf, result)
  i += bytes_read

proc to_string(data: seq[byte]): string =
  ## Convert seq[byte] to string efficiently.
  result = newString(data.len)
  if data.len > 0:
    copyMem(addr result[0], unsafeAddr data[0], data.len)

proc to_bytes(s: string): seq[byte] =
  ## Convert string to seq[byte] efficiently.
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

proc encode_rle_data*(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
  ## RLE encode a full chunk snapshot.
  ## Output format: format byte + sequential voxel bytes with REPEAT commands for runs of 3+.
  result = @[FMT_RLE]

  var i = 0
  while i < CHUNK_VOLUME:
    let current = voxels[i]
    var run_length = 1

    while i + run_length < CHUNK_VOLUME and
          voxels[i + run_length] == current and
          run_length < 258:
      inc run_length

    if run_length >= 3:
      result.add CMD_REPEAT
      result.add (run_length - 3).uint8
      result.add current
      i += run_length
    else:
      for _ in 0 ..< run_length:
        if current >= CMD_REPEAT:

          result.add CMD_REPEAT
          result.add 0'u8
          result.add current
        else:
          result.add current
        inc i

proc encode_sparse_data*(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
  ## Sparse encode a chunk - only non-empty voxels as (position, voxel) pairs.
  ## Format: format byte + varint count + (varint position, packed voxel) pairs
  result = @[FMT_SPARSE_FULL]

  # First pass: count non-empty voxels
  var count = 0
  for v in voxels:
    if v != EMPTY_VOXEL:
      inc count

  # Write count as varint
  var buf: array[maxVarIntLen, byte]
  let len = writeVu64(buf, count.uint64)
  for i in 0 ..< len:
    result.add buf[i]

  # Write position/voxel pairs
  for i, v in voxels:
    if v != EMPTY_VOXEL:
      let pos_len = writeVu64(buf, i.uint64)
      for j in 0 ..< pos_len:
        result.add buf[j]
      result.add v

proc decode_rle_data*(data: openArray[byte], start: int = 1): array[CHUNK_VOLUME, PackedVoxel] =
  ## Decode RLE snapshot into voxel array.
  ## Assumes data[0] is FMT_RLE (skipped via start parameter).
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

proc decode_sparse_data*(data: openArray[byte], start: int = 1): array[CHUNK_VOLUME, PackedVoxel] =
  ## Decode sparse snapshot into voxel array.
  ## Assumes data[0] is FMT_SPARSE_FULL (skipped via start parameter).
  var i = start

  # Read count
  var buf: array[maxVarIntLen, byte]
  let available = min(maxVarIntLen, data.len - i)
  for j in 0 ..< available:
    buf[j] = data[i + j]
  var count: uint64
  let count_len = readVu64(buf, count)
  i += count_len

  # Read position/voxel pairs
  for _ in 0 ..< count.int:
    let pos_available = min(maxVarIntLen, data.len - i)
    for j in 0 ..< pos_available:
      buf[j] = data[i + j]
    var pos: uint64
    let pos_len = readVu64(buf, pos)
    i += pos_len
    let voxel = data[i].PackedVoxel
    inc i
    if pos < CHUNK_VOLUME.uint64:
      result[pos.int] = voxel

type
  ChunkEncoding* = enum
    ceAdaptive  # Pick smaller of RLE/sparse
    ceRLE       # Always use RLE
    ceSparse    # Always use sparse

proc encode_chunk*(voxels: array[CHUNK_VOLUME, PackedVoxel],
                   encoding: ChunkEncoding = ceAdaptive): PackedChunk =
  ## Encode a chunk using the specified encoding strategy.
  ## For ceAdaptive, picks whichever encoding produces smaller output.

  # Check if chunk is empty
  var has_voxels = false
  for v in voxels:
    if v != EMPTY_VOXEL:
      has_voxels = true
      break

  if not has_voxels:
    return PackedChunk(data: $char(FMT_EMPTY))

  case encoding
  of ceRLE:
    result = PackedChunk(data: encode_rle_data(voxels).to_string)
  of ceSparse:
    result = PackedChunk(data: encode_sparse_data(voxels).to_string)
  of ceAdaptive:
    let rle = encode_rle_data(voxels)
    let sparse = encode_sparse_data(voxels)
    if rle.len <= sparse.len:
      result = PackedChunk(data: rle.to_string)
    else:
      result = PackedChunk(data: sparse.to_string)

proc decode_chunk*(packed: PackedChunk): array[CHUNK_VOLUME, PackedVoxel] =
  ## Decode a packed chunk back to voxel array.
  if packed.data.len == 0:
    return  # All zeros (empty)

  let format = packed.data[0].byte
  case format
  of FMT_RLE:
    result = decode_rle_data(packed.data.to_bytes, 1)
  of FMT_SPARSE_FULL, FMT_SPARSE_DELTA:
    result = decode_sparse_data(packed.data.to_bytes, 1)
  of FMT_EMPTY:
    discard  # Result is already all zeros
  else:
    raise newException(ValueError, "Unknown packed chunk format: " & $format)

proc is_empty*(packed: PackedChunk): bool =
  ## Check if a packed chunk represents an empty chunk.
  packed.data.len == 0 or (packed.data.len == 1 and packed.data[0].byte == FMT_EMPTY)

proc format_name*(packed: PackedChunk): string =
  ## Get a human-readable name for the encoding format.
  if packed.data.len == 0:
    return "empty"
  case packed.data[0].byte
  of FMT_RLE: "RLE"
  of FMT_SPARSE_FULL: "sparse"
  of FMT_SPARSE_DELTA: "delta"
  of FMT_EMPTY: "empty"
  else: "unknown"

proc encode_delta*(changes: openArray[tuple[pos: Vector3, voxel: PackedVoxel]]): DeltaUpdate =
  ## Encode a set of voxel changes into a delta update.
  ## Format: FMT_SPARSE_DELTA + varint count + (varint position, packed voxel) pairs
  result.data = $char(FMT_SPARSE_DELTA)

  var buf: array[maxVarIntLen, byte]
  let count_len = writeVu64(buf, changes.len.uint64)
  for i in 0 ..< count_len:
    result.data.add char(buf[i])

  for (pos, voxel) in changes:
    let linear = linear_position(pos)
    let pos_len = writeVu64(buf, linear.uint64)
    for j in 0 ..< pos_len:
      result.data.add char(buf[j])
    result.data.add char(voxel)

proc decode_delta*(delta: DeltaUpdate): seq[tuple[pos: Vector3, voxel: PackedVoxel]] =
  ## Decode a delta update back to position/voxel pairs.
  if delta.data.len == 0 or delta.data[0].byte != FMT_SPARSE_DELTA:
    return @[]

  var i = 1
  var buf: array[maxVarIntLen, byte]
  let available = min(maxVarIntLen, delta.data.len - i)
  for j in 0 ..< available:
    buf[j] = delta.data[i + j].byte
  var count: uint64
  let count_len = readVu64(buf, count)
  i += count_len

  for _ in 0 ..< count.int:
    let pos_available = min(maxVarIntLen, delta.data.len - i)
    for j in 0 ..< pos_available:
      buf[j] = delta.data[i + j].byte
    var linear: uint64
    let pos_len = readVu64(buf, linear)
    i += pos_len
    let voxel = delta.data[i].byte.PackedVoxel
    inc i
    result.add (from_linear(linear.int), voxel)

proc apply_delta*(voxels: var array[CHUNK_VOLUME, PackedVoxel], delta: DeltaUpdate) =
  ## Apply a delta update to a voxel array in place.
  for (pos, voxel) in decode_delta(delta):
    let linear = linear_position(pos)
    voxels[linear] = voxel

when is_main_module:
  import std/unittest

  suite "packed_chunks":
    test "pack/unpack voxel round-trip":
      for color_idx in 0 ..< 80:
        for kind_ord in 0 ..< 3:
          let packed = pack_voxel(color_idx, kind_ord)
          let (c, k) = unpack_voxel(packed)
          check c == color_idx
          check k == kind_ord

    test "empty voxel":
      let packed = pack_voxel(0, KIND_HOLE)
      check packed == EMPTY_VOXEL
      let (c, k) = unpack_voxel(EMPTY_VOXEL)
      check c == 0
      check k == KIND_HOLE

    test "linear position round-trip":
      for x in 0 ..< CHUNK_SIZE:
        for y in 0 ..< CHUNK_SIZE:
          for z in 0 ..< CHUNK_SIZE:
            let pos = vec3(x.float, y.float, z.float)
            let linear = linear_position(pos)
            let restored = from_linear(linear)
            check restored == pos

    test "linear position range":
      check linear_position(0, 0, 0) == 0
      check linear_position(15, 15, 15) == 4095

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

    test "RLE compression ratio":
      var uniform: array[CHUNK_VOLUME, PackedVoxel]
      for i in 0 ..< CHUNK_VOLUME:
        uniform[i] = 5

      let encoded = encode_rle_data(uniform)
      check encoded.len < 100
