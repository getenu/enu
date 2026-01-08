## Chunk encoding comparison test
## Compares RLE vs sparse array encoding for different chunk patterns

import std/[random, strformat, tables]
import models/[packed_chunks, colors]
import core

type
  TestChunk = array[CHUNK_VOLUME, PackedVoxel]

  # Sparse encoding: array of (linear_position, packed_voxel) pairs
  SparseEntry = tuple[pos: uint16, voxel: PackedVoxel]

proc count_non_empty(chunk: TestChunk): int =
  for v in chunk:
    if v != EMPTY_VOXEL:
      inc result

proc encode_sparse(chunk: TestChunk): seq[SparseEntry] =
  ## Encode as array of (position, voxel) pairs for non-empty voxels
  for i, v in chunk:
    if v != EMPTY_VOXEL:
      result.add (pos: i.uint16, voxel: v)

proc sparse_byte_size(entries: seq[SparseEntry]): int =
  ## Each entry: 2 bytes position + 1 byte voxel = 3 bytes
  entries.len * 3

proc sparse_varint_size(entries: seq[SparseEntry]): int =
  ## Position as varint (1-2 bytes for 0-4095) + 1 byte voxel
  for entry in entries:
    if entry.pos < 128:
      result += 2  # 1 byte varint + 1 byte voxel
    else:
      result += 3  # 2 byte varint + 1 byte voxel

# Test chunk generators

proc empty_chunk(): TestChunk =
  ## All empty
  discard  # Default is all zeros

proc full_uniform_chunk(color_idx: int = 1): TestChunk =
  ## All same color
  let packed = pack_voxel(color_idx, KIND_MANUAL)
  for i in 0 ..< CHUNK_VOLUME:
    result[i] = packed

proc full_random_chunk(seed: int = 42): TestChunk =
  ## All filled with random colors
  var rng = init_rand(seed)
  for i in 0 ..< CHUNK_VOLUME:
    let color_idx = rng.rand(6)  # 7 colors (0-6)
    let kind = rng.rand(2)  # 3 kinds (0-2)
    result[i] = pack_voxel(color_idx, kind)

proc sparse_random_chunk(fill_percent: float, seed: int = 42): TestChunk =
  ## Randomly filled to given percentage
  var rng = init_rand(seed)
  let target = int(CHUNK_VOLUME.float * fill_percent)
  var filled = 0
  while filled < target:
    let pos = rng.rand(CHUNK_VOLUME - 1)
    if result[pos] == EMPTY_VOXEL:
      let color_idx = rng.rand(6)
      result[pos] = pack_voxel(color_idx, KIND_MANUAL)
      inc filled

proc layered_chunk(): TestChunk =
  ## Horizontal layers of different colors (good for RLE)
  for i in 0 ..< CHUNK_VOLUME:
    let y = (i div CHUNK_SIZE) mod CHUNK_SIZE
    let color_idx = y mod 7
    result[i] = pack_voxel(color_idx, KIND_MANUAL)

proc striped_chunk(): TestChunk =
  ## Vertical stripes (tests RLE with medium runs)
  for i in 0 ..< CHUNK_VOLUME:
    let x = i div (CHUNK_SIZE * CHUNK_SIZE)
    let color_idx = x mod 7
    result[i] = pack_voxel(color_idx, KIND_MANUAL)

proc checkerboard_chunk(): TestChunk =
  ## 3D checkerboard (worst case for RLE)
  for i in 0 ..< CHUNK_VOLUME:
    let x = i div (CHUNK_SIZE * CHUNK_SIZE)
    let y = (i div CHUNK_SIZE) mod CHUNK_SIZE
    let z = i mod CHUNK_SIZE
    if (x + y + z) mod 2 == 0:
      result[i] = pack_voxel(1, KIND_MANUAL)
    # else empty

proc solid_cube_chunk(size: int = 8): TestChunk =
  ## Solid cube in center of chunk
  let offset = (CHUNK_SIZE - size) div 2
  for x in offset ..< offset + size:
    for y in offset ..< offset + size:
      for z in offset ..< offset + size:
        let i = linear_position(x, y, z)
        result[i] = pack_voxel(1, KIND_MANUAL)

proc hollow_cube_chunk(size: int = 12): TestChunk =
  ## Hollow cube (shell only)
  let offset = (CHUNK_SIZE - size) div 2
  for x in offset ..< offset + size:
    for y in offset ..< offset + size:
      for z in offset ..< offset + size:
        let on_edge = x == offset or x == offset + size - 1 or
                      y == offset or y == offset + size - 1 or
                      z == offset or z == offset + size - 1
        if on_edge:
          let i = linear_position(x, y, z)
          result[i] = pack_voxel(2, KIND_MANUAL)

proc scattered_points(count: int, seed: int = 42): TestChunk =
  ## Specific number of random points
  var rng = init_rand(seed)
  var placed = 0
  while placed < count:
    let pos = rng.rand(CHUNK_VOLUME - 1)
    if result[pos] == EMPTY_VOXEL:
      result[pos] = pack_voxel(rng.rand(6), KIND_MANUAL)
      inc placed

proc compare_encoding(name: string, chunk: TestChunk) =
  let non_empty = chunk.count_non_empty()
  let rle = encode_rle(chunk)
  let sparse = encode_sparse(chunk)

  let rle_size = rle.len
  let sparse_fixed = sparse_byte_size(sparse)
  let sparse_var = sparse_varint_size(sparse)

  let fill_pct = non_empty.float / CHUNK_VOLUME.float * 100

  echo &"{name:<25} voxels={non_empty:>4} ({fill_pct:>5.1f}%)  RLE={rle_size:>5}  sparse_fixed={sparse_fixed:>5}  sparse_var={sparse_var:>5}  best={min(rle_size, sparse_var):>5}"

when isMainModule:
  echo "Chunk Encoding Comparison"
  echo "========================="
  echo &"Chunk size: {CHUNK_SIZE}x{CHUNK_SIZE}x{CHUNK_SIZE} = {CHUNK_VOLUME} voxels"
  echo ""
  echo "Encoding sizes in bytes:"
  echo ""

  compare_encoding("Empty", empty_chunk())
  compare_encoding("Full uniform", full_uniform_chunk())
  compare_encoding("Full random", full_random_chunk())
  compare_encoding("Sparse 1%", sparse_random_chunk(0.01))
  compare_encoding("Sparse 5%", sparse_random_chunk(0.05))
  compare_encoding("Sparse 10%", sparse_random_chunk(0.10))
  compare_encoding("Sparse 25%", sparse_random_chunk(0.25))
  compare_encoding("Sparse 50%", sparse_random_chunk(0.50))
  compare_encoding("Layered (horizontal)", layered_chunk())
  compare_encoding("Striped (vertical)", striped_chunk())
  compare_encoding("Checkerboard 50%", checkerboard_chunk())
  compare_encoding("Solid 8x8x8 cube", solid_cube_chunk(8))
  compare_encoding("Solid 4x4x4 cube", solid_cube_chunk(4))
  compare_encoding("Hollow 12x12x12", hollow_cube_chunk(12))
  compare_encoding("Hollow 8x8x8", hollow_cube_chunk(8))
  compare_encoding("10 scattered points", scattered_points(10))
  compare_encoding("50 scattered points", scattered_points(50))
  compare_encoding("100 scattered points", scattered_points(100))
  compare_encoding("500 scattered points", scattered_points(500))
