## Voxel Storage and Encoding
##
## Simplified voxel management - packed format is the sync mechanism.
## Chunks start with a snapshot, then use deltas for incremental changes.
## Re-snapshot when: >100 voxels change at once, or >100 deltas accumulated.

import std/[varints, options, math]
import pkg/godot except print, Color
import godotapi/[voxel_buffer, voxel_tool]
import core
import models/colors

type ChunkFormat* {.size: sizeof(uint8).} = enum
  FMT_RLE = 0x00
  FMT_SPARSE_FULL = 0x01
  FMT_SPARSE_DELTA = 0x02
  FMT_EMPTY = 0x03

const CMD_REPEAT* = 241'u8

# =============================================================================
# Packing/Unpacking
# =============================================================================

proc pack_voxel*(color_index: int, kind_ord: int): PackedVoxel =
  if color_index == 0 and kind_ord == 0: # Hole
    EMPTY_VOXEL
  else:
    ((color_index * 3) + kind_ord + 1).PackedVoxel

proc unpack_voxel*(
    packed: PackedVoxel
): tuple[color_index: int, kind_ord: int] =
  if packed == EMPTY_VOXEL:
    (0, 0)
  else:
    let val = packed.int - 1
    (val div 3, val mod 3)

# =============================================================================
# Position Conversion
# =============================================================================

proc linear_position*(x, y, z: int): int {.inline.} =
  z + y * ChunkDim + x * ChunkDim * ChunkDim

proc floor_mod(a, b: int): int {.inline.} =
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

proc chunk_to_local*(chunk_id: Vector3, pos: Vector3): int =
  let local_x = floor_mod(pos.x.int - (chunk_id.x.int * 16), 16)
  let local_y = floor_mod(pos.y.int - (chunk_id.y.int * 16), 16)
  let local_z = floor_mod(pos.z.int - (chunk_id.z.int * 16), 16)
  linear_position(local_x, local_y, local_z)

# =============================================================================
# Varint Helpers
# =============================================================================

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

# =============================================================================
# RLE Encoding/Decoding
# =============================================================================

proc encode_rle_data*(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
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

proc decode_rle_data*(
    data: openArray[byte], start: int = 1
): array[CHUNK_VOLUME, PackedVoxel] =
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

# =============================================================================
# Sparse Encoding/Decoding
# =============================================================================

proc encode_sparse_data*(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
  result = @[FMT_SPARSE_FULL.byte]
  var count = 0
  for v in voxels:
    if v != EMPTY_VOXEL:
      inc count

  var buf: array[max_var_int_len, byte]
  let len = write_vu64(buf, count.uint64)
  for i in 0 ..< len:
    result.add buf[i]

  for i, v in voxels:
    if v != EMPTY_VOXEL:
      let pos_len = write_vu64(buf, i.uint64)
      for j in 0 ..< pos_len:
        result.add buf[j]
      result.add v

proc decode_sparse_data*(
    data: openArray[byte], start: int = 1
): array[CHUNK_VOLUME, PackedVoxel] =
  var i = start
  var buf: array[max_var_int_len, byte]
  let available = min(max_var_int_len, data.len - i)
  for j in 0 ..< available:
    buf[j] = data[i + j]
  var count: uint64
  let count_len = read_vu64(buf, count)
  i += count_len

  for _ in 0 ..< count.int:
    let pos_available = min(max_var_int_len, data.len - i)
    for j in 0 ..< pos_available:
      buf[j] = data[i + j]
    var pos: uint64
    let pos_len = read_vu64(buf, pos)
    i += pos_len
    let voxel = data[i].byte.PackedVoxel
    inc i
    if pos < CHUNK_VOLUME.uint64:
      result[pos.int] = voxel

# =============================================================================
# Chunk Encoding/Decoding
# =============================================================================

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

proc decode_chunk*(packed: PackedChunk): array[CHUNK_VOLUME, PackedVoxel] =
  if packed.data.len == 0:
    return

  let format = ChunkFormat(packed.data[0].byte)
  case format
  of FMT_RLE:
    result = decode_rle_data(packed.data.to_bytes, 1)
  of FMT_SPARSE_FULL, FMT_SPARSE_DELTA:
    result = decode_sparse_data(packed.data.to_bytes, 1)
  of FMT_EMPTY:
    discard

proc is_empty*(packed: PackedChunk): bool =
  packed.data.len == 0 or
    (packed.data.len == 1 and packed.data[0].byte == FMT_EMPTY.byte)

# =============================================================================
# Delta Encoding/Decoding
# =============================================================================

proc encode_delta*(
    changes: openArray[tuple[pos: Vector3, voxel: PackedVoxel]]
): DeltaUpdate =
  result.data = $char(FMT_SPARSE_DELTA.byte)
  var buf: array[max_var_int_len, byte]
  let count_len = write_vu64(buf, changes.len.uint64)
  for i in 0 ..< count_len:
    result.data.add char(buf[i])

  for (pos, voxel) in changes:
    let linear = linear_position(pos)
    let pos_len = write_vu64(buf, linear.uint64)
    for j in 0 ..< pos_len:
      result.data.add char(buf[j])
    result.data.add char(voxel)

proc decode_delta*(
    delta: DeltaUpdate
): seq[tuple[pos: Vector3, voxel: PackedVoxel]] =
  if delta.data.len == 0 or delta.data[0].byte != FMT_SPARSE_DELTA.byte:
    return @[]

  var i = 1
  var buf: array[max_var_int_len, byte]
  let available = min(max_var_int_len, delta.data.len - i)
  for j in 0 ..< available:
    buf[j] = delta.data[i + j].byte
  var count: uint64
  let count_len = read_vu64(buf, count)
  i += count_len

  for _ in 0 ..< count.int:
    let pos_available = min(max_var_int_len, delta.data.len - i)
    for j in 0 ..< pos_available:
      buf[j] = delta.data[i + j].byte
    var linear: uint64
    let pos_len = read_vu64(buf, linear)
    i += pos_len
    let voxel = delta.data[i].byte.PackedVoxel
    inc i
    result.add (from_linear(linear.int), voxel)

# =============================================================================
# VoxelStore Init
# =============================================================================

proc init*(
    _: type VoxelStore,
    id: string,
    ctx: EdContext = nil,
    unit_id: string = "",
    edit_snapshots: EdTable[EditKey, SnapshotData] = nil,
    edit_deltas: EdTable[EditKey, EdSeq[DeltaUpdate]] = nil,
): VoxelStore =
  let use_ctx = if ctx.isNil: Ed.thread_ctx else: ctx
  VoxelStore(
    id: id,
    ctx: use_ctx,
    unit_id: unit_id,
    packed_chunks: EdTable[Vector3, SnapshotData].init(
      id = id & ".packed_chunks",
      ctx = use_ctx,
      flags = {SYNC_LOCAL, SYNC_REMOTE},
    ),
    chunk_deltas: EdTable[Vector3, EdSeq[DeltaUpdate]].init(
      id = id & ".chunk_deltas",
      ctx = use_ctx,
      flags = {SYNC_LOCAL, SYNC_REMOTE},
    ),
    edit_snapshots: edit_snapshots,
    edit_deltas: edit_deltas,
  )

# =============================================================================
# Local Voxel Access
# =============================================================================

proc contains*(self: VoxelStore, position: Vector3): bool =
  let chunk_id = position.buffer
  chunk_id in self.local_voxels and position in self.local_voxels[chunk_id]

proc voxel_info*(self: VoxelStore, position: Vector3): VoxelInfo =
  let chunk_id = position.buffer
  self.local_voxels[chunk_id][position]

proc find_voxel*(self: VoxelStore, position: Vector3): Option[VoxelInfo] =
  let chunk_id = position.buffer
  if chunk_id in self.local_voxels and position in self.local_voxels[chunk_id]:
    some(self.local_voxels[chunk_id][position])
  else:
    none(VoxelInfo)

# =============================================================================
# Voxel Modification
# =============================================================================

proc add_voxel*(self: VoxelStore, position: Vector3, voxel: VoxelInfo) =
  let chunk_id = position.buffer

  let is_new_chunk = chunk_id notin self.local_voxels
  if is_new_chunk:
    self.local_voxels[chunk_id] = Table[Vector3, VoxelInfo].init
    if not self.on_chunk_created.isNil:
      self.on_chunk_created(chunk_id)

  let existed = position in self.local_voxels[chunk_id]
  if not existed:
    inc self.block_count

  self.local_voxels[chunk_id][position] = voxel

  let local_pos = vec3(
    floor_mod(position.x.int, 16).float,
    floor_mod(position.y.int, 16).float,
    floor_mod(position.z.int, 16).float,
  )
  let packed = pack_voxel(voxel.color.action_index.ord, voxel.kind.ord)
  self.pending_chunks.mgetOrPut(chunk_id, @[]).add (local_pos, packed)

proc del_voxel*(self: VoxelStore, position: Vector3) =
  let chunk_id = position.buffer
  if chunk_id in self.local_voxels and position in self.local_voxels[chunk_id]:
    dec self.block_count
    self.local_voxels[chunk_id].del(position)

    let local_pos = vec3(
      floor_mod(position.x.int, 16).float,
      floor_mod(position.y.int, 16).float,
      floor_mod(position.z.int, 16).float,
    )
    self.pending_chunks.mgetOrPut(chunk_id, @[]).add (local_pos, EMPTY_VOXEL)

# =============================================================================
# Edit Access (uses local_edits cache)
# =============================================================================

proc has_edit*(self: VoxelStore, position: Vector3): bool =
  let chunk_id = chunk_id_for_pos(position)
  let local_pos = local_pos_in_chunk(position)
  chunk_id in self.local_edits and local_pos in self.local_edits[chunk_id]

proc get_edit*(self: VoxelStore, position: Vector3): VoxelInfo =
  let chunk_id = chunk_id_for_pos(position)
  let local_pos = local_pos_in_chunk(position)
  self.local_edits[chunk_id][local_pos]

proc set_edit*(self: VoxelStore, position: Vector3, info: VoxelInfo) =
  let chunk_id = chunk_id_for_pos(position)
  let local_pos = local_pos_in_chunk(position)

  if chunk_id notin self.local_edits:
    self.local_edits[chunk_id] = Table[Vector3, VoxelInfo].init
  self.local_edits[chunk_id][local_pos] = info

  let packed = pack_voxel(info.color.action_index.ord, info.kind.ord)
  self.pending_edits.mgetOrPut(chunk_id, @[]).add (local_pos, packed)

proc del_edit*(self: VoxelStore, position: Vector3) =
  let chunk_id = chunk_id_for_pos(position)
  let local_pos = local_pos_in_chunk(position)

  if chunk_id in self.local_edits and local_pos in self.local_edits[chunk_id]:
    self.local_edits[chunk_id].del(local_pos)
    if self.local_edits[chunk_id].len == 0:
      self.local_edits.del(chunk_id)

    self.pending_edits.mgetOrPut(chunk_id, @[]).add (local_pos, EMPTY_VOXEL)

template for_all_edits*(self: VoxelStore, body: untyped) =
  for chunk_id, chunk in self.local_edits:
    for local_pos, info {.inject.} in chunk:
      let pos {.inject.} = vec3(
        chunk_id.x * ChunkDim + local_pos.x,
        chunk_id.y * ChunkDim + local_pos.y,
        chunk_id.z * ChunkDim + local_pos.z,
      )
      body

proc rebuild_local_edits*(self: VoxelStore) =
  self.local_edits.clear()

  if self.edit_snapshots.isNil:
    return

  for key, snapshot in self.edit_snapshots:
    if key.id != self.unit_id:
      continue
    let chunk_id = key.loc
    let voxels = decode_chunk(snapshot)
    for linear in 0 ..< CHUNK_VOLUME:
      let packed_voxel = voxels[linear]
      if packed_voxel != EMPTY_VOXEL:
        let (color_idx, kind_ord) = unpack_voxel(packed_voxel)
        let local_pos = from_linear(linear)
        if chunk_id notin self.local_edits:
          self.local_edits[chunk_id] = Table[Vector3, VoxelInfo].init
        self.local_edits[chunk_id][local_pos] =
          (VoxelKind(kind_ord), ACTION_COLORS[Colors(color_idx)])

  if self.edit_deltas.isNil:
    return

  for key, delta_seq in self.edit_deltas:
    if key.id != self.unit_id or delta_seq.isNil:
      continue
    let chunk_id = key.loc
    for delta in delta_seq:
      let changes = decode_delta(delta)
      for (local_pos, packed_voxel) in changes:
        if packed_voxel == EMPTY_VOXEL:
          if chunk_id in self.local_edits:
            self.local_edits[chunk_id].del(local_pos)
        else:
          let (color_idx, kind_ord) = unpack_voxel(packed_voxel)
          if chunk_id notin self.local_edits:
            self.local_edits[chunk_id] = Table[Vector3, VoxelInfo].init
          self.local_edits[chunk_id][local_pos] =
            (VoxelKind(kind_ord), ACTION_COLORS[Colors(color_idx)])

# =============================================================================
# Unified Flush Helpers
# =============================================================================

proc should_use_snapshot(
    has_existing: bool, change_count, delta_count: int, is_empty: bool
): bool =
  not has_existing or change_count > MAX_CHANGES_FOR_DELTA or
    delta_count >= MAX_DELTAS_BEFORE_SNAPSHOT or is_empty

proc build_chunk_state(
    self: VoxelStore, chunk_id: Vector3
): array[CHUNK_VOLUME, PackedVoxel] =
  if chunk_id in self.local_voxels:
    for pos, info in self.local_voxels[chunk_id]:
      let linear = chunk_to_local(chunk_id, pos)
      result[linear] = pack_voxel(info.color.action_index.ord, info.kind.ord)

proc build_edit_state(
    self: VoxelStore, chunk_id: Vector3
): array[CHUNK_VOLUME, PackedVoxel] =
  if chunk_id in self.local_edits:
    for local_pos, info in self.local_edits[chunk_id]:
      let linear = linear_position(local_pos)
      if linear >= 0 and linear < CHUNK_VOLUME:
        result[linear] = pack_voxel(info.color.action_index.ord, info.kind.ord)

# =============================================================================
# Flush Chunks
# =============================================================================

proc flush_chunk_snapshot(self: VoxelStore, chunk_id: Vector3) =
  let voxels = self.build_chunk_state(chunk_id)
  let packed = encode_chunk(voxels)

  if packed.is_empty:
    if chunk_id in self.packed_chunks:
      self.packed_chunks.del(chunk_id)
    if chunk_id in self.chunk_deltas:
      self.chunk_deltas.del(chunk_id)
  else:
    self.packed_chunks[chunk_id] = packed
    if chunk_id in self.chunk_deltas:
      self.chunk_deltas[chunk_id].clear

  inc self.snapshots_flushed

proc flush_chunk_delta(
    self: VoxelStore,
    chunk_id: Vector3,
    changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]],
) =
  let delta = encode_delta(changes)

  if chunk_id notin self.chunk_deltas:
    self.chunk_deltas[chunk_id] =
      EdSeq[DeltaUpdate].init(flags = {SYNC_LOCAL, SYNC_REMOTE})

  self.chunk_deltas[chunk_id].add delta
  inc self.deltas_flushed

proc flush_dirty_chunks*(self: VoxelStore) =
  for chunk_id, changes in self.pending_chunks:
    let has_snapshot = chunk_id in self.packed_chunks
    let delta_count =
      if chunk_id in self.chunk_deltas:
        self.chunk_deltas[chunk_id].len
      else:
        0
    let chunk_empty =
      chunk_id notin self.local_voxels or self.local_voxels[chunk_id].len == 0

    if should_use_snapshot(has_snapshot, changes.len, delta_count, chunk_empty):
      self.flush_chunk_snapshot(chunk_id)
    else:
      self.flush_chunk_delta(chunk_id, changes)

  self.pending_chunks.clear

# =============================================================================
# Flush Edits
# =============================================================================

proc flush_edit_snapshot(self: VoxelStore, chunk_id: Vector3) =
  let key: EditKey = (self.unit_id, chunk_id)
  let voxels = self.build_edit_state(chunk_id)
  let packed = encode_chunk(voxels)

  if packed.is_empty:
    if key in self.edit_snapshots:
      self.edit_snapshots.del(key)
    if key in self.edit_deltas:
      self.edit_deltas.del(key)
  else:
    self.edit_snapshots[key] = packed
    if key in self.edit_deltas:
      self.edit_deltas[key].clear

  inc self.snapshots_flushed

proc flush_edit_delta(
    self: VoxelStore,
    chunk_id: Vector3,
    changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]],
) =
  let key: EditKey = (self.unit_id, chunk_id)
  let delta = encode_delta(changes)

  if key notin self.edit_deltas:
    self.edit_deltas[key] =
      EdSeq[DeltaUpdate].init(ctx = self.ctx, flags = {SYNC_LOCAL, SYNC_REMOTE})

  self.edit_deltas[key].add delta
  inc self.deltas_flushed

proc flush_dirty_edits*(self: VoxelStore) =
  if self.edit_snapshots.isNil:
    return

  for chunk_id, changes in self.pending_edits:
    let key: EditKey = (self.unit_id, chunk_id)
    let has_snapshot = key in self.edit_snapshots
    let delta_count =
      if key in self.edit_deltas:
        self.edit_deltas[key].len
      else:
        0
    let chunk_empty =
      chunk_id notin self.local_edits or self.local_edits[chunk_id].len == 0

    if should_use_snapshot(has_snapshot, changes.len, delta_count, chunk_empty):
      self.flush_edit_snapshot(chunk_id)
    else:
      self.flush_edit_delta(chunk_id, changes)

  self.pending_edits.clear

# =============================================================================
# Receiving (for rebuilding local_voxels from packed data)
# =============================================================================

proc apply_snapshot*(
    self: VoxelStore, chunk_id: Vector3, snapshot: SnapshotData
) =
  if snapshot.data.len == 0:
    return

  let voxels = decode_chunk(snapshot)

  if chunk_id in self.local_voxels:
    for pos, info in self.local_voxels[chunk_id]:
      if info.kind != HOLE:
        dec self.block_count
    self.local_voxels.del(chunk_id)

  var has_voxels = false
  for v in voxels:
    if v != EMPTY_VOXEL:
      has_voxels = true
      break

  if has_voxels:
    self.local_voxels[chunk_id] = Table[Vector3, VoxelInfo].init
    for linear in 0 ..< CHUNK_VOLUME:
      let packed_voxel = voxels[linear]
      if packed_voxel != EMPTY_VOXEL:
        let (color_idx, kind_ord) = unpack_voxel(packed_voxel)
        let pos = from_linear(linear)
        let world_pos = vec3(
          chunk_id.x * 16 + pos.x,
          chunk_id.y * 16 + pos.y,
          chunk_id.z * 16 + pos.z,
        )
        let color = ACTION_COLORS[Colors(color_idx)]
        let kind = VoxelKind(kind_ord)
        self.local_voxels[chunk_id][world_pos] = (kind, color)
        if kind != HOLE:
          inc self.block_count

proc apply_delta*(self: VoxelStore, chunk_id: Vector3, delta: DeltaUpdate) =
  let changes = decode_delta(delta)
  for (local_pos, packed_voxel) in changes:
    let world_pos = vec3(
      chunk_id.x * 16 + local_pos.x,
      chunk_id.y * 16 + local_pos.y,
      chunk_id.z * 16 + local_pos.z,
    )

    if packed_voxel == EMPTY_VOXEL:
      if chunk_id in self.local_voxels and
          world_pos in self.local_voxels[chunk_id]:
        let info = self.local_voxels[chunk_id][world_pos]
        if info.kind != HOLE:
          dec self.block_count
        self.local_voxels[chunk_id].del(world_pos)
    else:
      let (color_idx, kind_ord) = unpack_voxel(packed_voxel)
      let color = ACTION_COLORS[Colors(color_idx)]
      let kind = VoxelKind(kind_ord)

      if chunk_id notin self.local_voxels:
        self.local_voxels[chunk_id] = Table[Vector3, VoxelInfo].init

      let existed = world_pos in self.local_voxels[chunk_id]
      if existed:
        let old_info = self.local_voxels[chunk_id][world_pos]
        if old_info.kind != HOLE:
          dec self.block_count

      self.local_voxels[chunk_id][world_pos] = (kind, color)
      if kind != HOLE:
        inc self.block_count

proc clear*(self: VoxelStore) =
  self.local_voxels.clear
  let packed = self.packed_chunks.value
  for chunk_id in packed.keys:
    self.packed_chunks.del(chunk_id)
  let deltas = self.chunk_deltas.value
  for chunk_id in deltas.keys:
    self.chunk_deltas.del(chunk_id)
  self.pending_chunks.clear
  self.block_count = 0

# =============================================================================
# Iterator for all voxels
# =============================================================================

iterator all_voxels*(self: VoxelStore): tuple[pos: Vector3, info: VoxelInfo] =
  for chunk_id, chunk in self.local_voxels:
    for pos, info in chunk:
      yield (pos, info)

# =============================================================================
# Direct Rendering (non-ASAP mode) - uses set_voxel for each voxel
# =============================================================================

proc render_snapshot_direct*(
    voxel_tool: VoxelTool, chunk_id: Vector3, snapshot: SnapshotData
) =
  if snapshot.data.len == 0:
    return
  let voxels = decode_chunk(snapshot)
  for linear in 0 ..< CHUNK_VOLUME:
    let packed_voxel = voxels[linear]
    if packed_voxel != EMPTY_VOXEL:
      let local_pos = from_linear(linear)
      let world_pos = chunk_id * ChunkDim + local_pos
      let (color_idx, _) = unpack_voxel(packed_voxel)
      voxel_tool.set_voxel(world_pos, color_idx.int64)

proc render_delta_direct*(
    voxel_tool: VoxelTool, chunk_id: Vector3, delta: DeltaUpdate
) =
  if delta.data.len == 0:
    return
  let changes = decode_delta(delta)
  for (local_pos, packed_voxel) in changes:
    let world_pos = chunk_id * ChunkDim + local_pos
    if packed_voxel == EMPTY_VOXEL:
      voxel_tool.set_voxel(world_pos, 0)
    else:
      let (color_idx, _) = unpack_voxel(packed_voxel)
      voxel_tool.set_voxel(world_pos, color_idx.int64)

# =============================================================================
# VoxelRenderer - ASAP Mode Buffer Rendering
# =============================================================================

import std/[monotimes, times]

const ASAP_PASTE_INTERVAL = initDuration(seconds = 2)

type VoxelRenderer* = ref object
  voxel_tool*: VoxelTool
  buffer: VoxelBuffer
  min_pos: Vector3
  max_pos: Vector3
  buffer_size: Vector3
  dirty: bool
  asap_active: bool
  last_paste_time: MonoTime

proc init*(_: type VoxelRenderer): VoxelRenderer =
  VoxelRenderer()

proc ensure_buffer(self: VoxelRenderer, chunk_id: Vector3) =
  let chunk_min = chunk_id * ChunkDim
  let chunk_max = chunk_min + vec3(ChunkDim - 1, ChunkDim - 1, ChunkDim - 1)

  if self.buffer.isNil:
    self.min_pos = chunk_min
    self.max_pos = chunk_max
    self.buffer_size = vec3(ChunkDim, ChunkDim, ChunkDim)
    self.buffer = gdnew[VoxelBuffer]()
    self.buffer.create(ChunkDim, ChunkDim, ChunkDim)
    self.buffer.fill(0)
  elif chunk_min.x < self.min_pos.x or chunk_min.y < self.min_pos.y or
      chunk_min.z < self.min_pos.z or chunk_max.x > self.max_pos.x or
      chunk_max.y > self.max_pos.y or chunk_max.z > self.max_pos.z:
    let new_min = vec3(
      min(chunk_min.x, self.min_pos.x),
      min(chunk_min.y, self.min_pos.y),
      min(chunk_min.z, self.min_pos.z),
    )
    let new_max = vec3(
      max(chunk_max.x, self.max_pos.x),
      max(chunk_max.y, self.max_pos.y),
      max(chunk_max.z, self.max_pos.z),
    )
    let new_size = new_max - new_min + vec3(1, 1, 1)

    let new_buffer = gdnew[VoxelBuffer]()
    new_buffer.create(new_size.x.int64, new_size.y.int64, new_size.z.int64)
    new_buffer.fill(0)

    let offset = self.min_pos - new_min
    new_buffer.copy_channel_from_area(
      self.buffer, vec3(0, 0, 0), self.buffer_size, offset, 0
    )

    self.buffer = new_buffer
    self.min_pos = new_min
    self.max_pos = new_max
    self.buffer_size = new_size

proc buffer_snapshot*(
    self: VoxelRenderer, chunk_id: Vector3, snapshot: SnapshotData
) =
  if snapshot.data.len == 0:
    return
  self.ensure_buffer(chunk_id)
  let voxels = decode_chunk(snapshot)
  for linear in 0 ..< CHUNK_VOLUME:
    let packed_voxel = voxels[linear]
    if packed_voxel != EMPTY_VOXEL:
      let local_pos = from_linear(linear)
      let world_pos = chunk_id * ChunkDim + local_pos
      let buffer_pos = world_pos - self.min_pos
      let (color_idx, _) = unpack_voxel(packed_voxel)
      self.buffer.set_voxel(
        color_idx.int64, buffer_pos.x.int64, buffer_pos.y.int64,
        buffer_pos.z.int64,
      )
  self.dirty = true

proc buffer_delta*(self: VoxelRenderer, chunk_id: Vector3, delta: DeltaUpdate) =
  if delta.data.len == 0:
    return
  self.ensure_buffer(chunk_id)
  let changes = decode_delta(delta)
  for (local_pos, packed_voxel) in changes:
    let world_pos = chunk_id * ChunkDim + local_pos
    let buffer_pos = world_pos - self.min_pos
    if packed_voxel == EMPTY_VOXEL:
      self.buffer.set_voxel(
        0, buffer_pos.x.int64, buffer_pos.y.int64, buffer_pos.z.int64
      )
    else:
      let (color_idx, _) = unpack_voxel(packed_voxel)
      self.buffer.set_voxel(
        color_idx.int64, buffer_pos.x.int64, buffer_pos.y.int64,
        buffer_pos.z.int64,
      )
  self.dirty = true

proc begin_asap*(self: VoxelRenderer) =
  self.buffer = nil
  self.min_pos = vec3()
  self.max_pos = vec3()
  self.buffer_size = vec3()
  self.dirty = false
  self.asap_active = true
  self.last_paste_time = get_mono_time()

proc tick_asap*(self: VoxelRenderer) =
  if not self.asap_active:
    return
  let now = get_mono_time()
  let elapsed = now - self.last_paste_time
  if elapsed >= ASAP_PASTE_INTERVAL:
    if not self.buffer.isNil and self.dirty and not self.voxel_tool.isNil:
      self.voxel_tool.paste(self.min_pos, self.buffer, 1, 0)
      self.dirty = false
    self.last_paste_time = now

proc end_asap*(self: VoxelRenderer) =
  if not self.buffer.isNil and self.dirty and not self.voxel_tool.isNil:
    self.voxel_tool.paste(self.min_pos, self.buffer, 1, 0)
  self.buffer = nil
  self.min_pos = vec3()
  self.max_pos = vec3()
  self.buffer_size = vec3()
  self.dirty = false
  self.asap_active = false
