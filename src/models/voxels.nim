import std/[varints, options, math, tables, monotimes, times, sequtils]
import pkg/godot except print, Color
import godotapi/[voxel_buffer, voxel_tool]
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

proc shared_of(self: VoxelStore): Shared =
  if ?self.build: self.build.shared_value.value else: nil

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

proc fits_8bit(voxels: array[CHUNK_VOLUME, PackedVoxel]): bool =
  for v in voxels:
    if v > 255:
      return false
  true

proc encode_rle8_data(voxels: array[CHUNK_VOLUME, PackedVoxel]): seq[byte] =
  ## Legacy FMT_RLE: 1 byte per voxel with the CMD_REPEAT escape. Only valid
  ## when every value fits a byte; old builds can decode it.
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
        if current >= CMD_REPEAT:
          result.add CMD_REPEAT
          result.add 0'u8
          result.add current.uint8
        else:
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
  ## Chunks whose values all fit a byte (pure named colors, and the first
  ## ~16 static palette entries) keep the legacy 1-byte format — identical
  ## wire size to before, decodable by old builds. Wider values escalate the
  ## chunk to FMT_RLE16.
  if fits_8bit(voxels):
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
  of FMT_RLE16:
    result = decode_rle16_data(packed.data.to_bytes, 1)
  of FMT_SPARSE_FULL16, FMT_SPARSE_DELTA16:
    result = decode_sparse_data(packed.data.to_bytes, 1, wide = true)
  of FMT_EMPTY:
    discard

proc is_empty*(packed: PackedChunk): bool =
  packed.data.len == 0 or
    (packed.data.len == 1 and packed.data[0].byte == FMT_EMPTY.byte)

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

proc init*(
    _: type VoxelStore,
    ctx: EdContext = nil,
    unit_id: string = "",
    build: Build = nil,
    edit_snapshots: EdTable[EditKey, SnapshotData] = nil,
    edit_deltas: EdTable[EditKey, EdSeq[DeltaUpdate]] = nil,
): VoxelStore =
  # The synced tables (`packed_chunks`/`chunk_deltas`) are the Build's own Ed
  # fields, read live through `build` (not cached) so a reload that reincarnates
  # them is always seen. The wrapper holds no ed identity, just local render
  # state. (Those tables are LAZY: pull-only on partial replicas, which page
  # chunks in/out; full replicas get the data.)
  let use_ctx = if not ?ctx: Ed.thread_ctx else: ctx
  VoxelStore(
    ctx: use_ctx,
    unit_id: unit_id,
    build: build,
    edit_snapshots: edit_snapshots,
    edit_deltas: edit_deltas,
  )

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
      result[linear] =
        pack_voxel(pack_color_index(self.shared_of, info.color), info.kind.ord)

proc build_edit_state(
    self: VoxelStore, chunk_id: Vector3
): array[CHUNK_VOLUME, PackedVoxel] =
  if chunk_id in self.local_edits:
    for local_pos, info in self.local_edits[chunk_id]:
      let linear = linear_position(local_pos)
      if linear >= 0 and linear < CHUNK_VOLUME:
        result[linear] =
          pack_voxel(pack_color_index(self.shared_of, info.color), info.kind.ord)

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
    # Own the nested seq under its table's owner (the build): it's created here
    # during drawing — outside any own scope — and an unowned container escapes
    # the destroy cascade, leaking on every reload.
    let table_owner = self.chunk_deltas.owner_id
    table_owner.own:
      self.chunk_deltas[chunk_id] =
        EdSeq[DeltaUpdate].init(flags = {SYNC_LOCAL, SYNC_REMOTE})

  self.chunk_deltas[chunk_id].add delta
  inc self.deltas_flushed

iterator flush_dirty_chunks*(self: VoxelStore): Vector3 =
  ## Flush each dirty chunk as one synced message, yielding its id after it's
  ## flushed and removed from `pending_chunks`. The caller drives the cadence and
  ## may stop early -- the worker breaks on channel pressure -- leaving the
  ## remaining chunks to coalesce and flush on a later frame, so a single large
  ## (ASAP) draw burst can't overshoot the channel in one go. Drain it fully (the
  ## `proc` overload below) to flush everything, e.g. for save / end_asap.
  for chunk_id in self.pending_chunks.keys.to_seq:
    let changes = self.pending_chunks[chunk_id]
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
    self.pending_chunks.del chunk_id
    yield chunk_id

proc flush_dirty_chunks*(self: VoxelStore) =
  ## Flush every dirty chunk (save / end_asap). The worker uses the iterator form
  ## to flush incrementally and stop under channel pressure.
  for _ in self.flush_dirty_chunks():
    discard

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
    # Own the nested seq under its table's owner (the Shared) — same leak as
    # flush_chunk_delta above.
    let table_owner = self.edit_deltas.owner_id
    table_owner.own:
      self.edit_deltas[key] = EdSeq[DeltaUpdate].init(
        ctx = self.ctx, flags = {SYNC_LOCAL, SYNC_REMOTE}
      )

  self.edit_deltas[key].add delta
  inc self.deltas_flushed

proc flush_dirty_edits*(self: VoxelStore) =
  if not ?self.edit_snapshots:
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

proc rebuild_local_edits*(self: VoxelStore)
proc set_edit*(self: VoxelStore, position: Vector3, info: VoxelInfo)
proc flush_edits_for_save*(self: VoxelStore) =
  ## Flushes all pending edits to snapshots so they are included in save data
  self.flush_dirty_edits()
  {.cast(gcsafe).}:
    self.rebuild_local_edits()
  for chunk_id in self.local_edits.keys:
    self.flush_edit_snapshot(chunk_id)

proc add_voxel*(self: VoxelStore, position: Vector3, voxel: VoxelInfo) =
  let chunk_id = position.buffer

  let is_new_chunk = chunk_id notin self.local_voxels
  if is_new_chunk:
    self.local_voxels[chunk_id] = Table[Vector3, VoxelInfo].init
    if not self.on_chunk_created.is_nil:
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
  let packed =
    pack_voxel(pack_color_index(self.shared_of, voxel.color), voxel.kind.ord)

  if self.ctx.metrics_label == "main" or self.immediate:
    self.flush_chunk_delta(chunk_id, @[(local_pos, packed)])
    let delta_count =
      if chunk_id in self.chunk_deltas:
        self.chunk_deltas[chunk_id].len
      else:
        0
    if should_use_snapshot(
      chunk_id in self.packed_chunks, 1, delta_count, false
    ):
      self.flush_chunk_snapshot(chunk_id)
  else:
    self.pending_chunks.mgetOrPut(chunk_id, @[]).add (local_pos, packed)

  if voxel.kind == MANUAL:
    {.cast(gcsafe).}:
      self.set_edit(position, voxel)

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
    let packed = EMPTY_VOXEL

    if self.ctx.metrics_label == "main" or self.immediate:
      self.flush_chunk_delta(chunk_id, @[(local_pos, packed)])
      let delta_count =
        if chunk_id in self.chunk_deltas:
          self.chunk_deltas[chunk_id].len
        else:
          0
      let chunk_empty = self.local_voxels[chunk_id].len == 0
      if should_use_snapshot(
        chunk_id in self.packed_chunks, 1, delta_count, chunk_empty
      ):
        self.flush_chunk_snapshot(chunk_id)
    else:
      self.pending_chunks.mgetOrPut(chunk_id, @[]).add (local_pos, packed)

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

  let packed =
    pack_voxel(pack_color_index(self.shared_of, info.color), info.kind.ord)

  if self.ctx.metrics_label == "main" or self.immediate:
    self.flush_edit_delta(chunk_id, @[(local_pos, packed)])
    let key: EditKey = (self.unit_id, chunk_id)
    let delta_count =
      if key in self.edit_deltas:
        self.edit_deltas[key].len
      else:
        0
    if should_use_snapshot(key in self.edit_snapshots, 1, delta_count, false):
      self.flush_edit_snapshot(chunk_id)
  else:
    self.pending_edits.mgetOrPut(chunk_id, @[]).add (local_pos, packed)

proc del_edit*(self: VoxelStore, position: Vector3) =
  let chunk_id = chunk_id_for_pos(position)
  let local_pos = local_pos_in_chunk(position)

  if chunk_id in self.local_edits and local_pos in self.local_edits[chunk_id]:
    self.local_edits[chunk_id].del(local_pos)
    if self.local_edits[chunk_id].len == 0:
      self.local_edits.del(chunk_id)

    let packed = EMPTY_VOXEL
    if self.ctx.metrics_label == "main" or self.immediate:
      self.flush_edit_delta(chunk_id, @[(local_pos, packed)])
      let key: EditKey = (self.unit_id, chunk_id)
      let delta_count =
        if key in self.edit_deltas:
          self.edit_deltas[key].len
        else:
          0
      let chunk_empty =
        chunk_id notin self.local_edits or self.local_edits[chunk_id].len == 0
      if should_use_snapshot(
        key in self.edit_snapshots, 1, delta_count, chunk_empty
      ):
        self.flush_edit_snapshot(chunk_id)
    else:
      self.pending_edits.mgetOrPut(chunk_id, @[]).add (local_pos, packed)

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

  if not ?self.edit_snapshots:
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
          (VoxelKind(kind_ord), resolve_color(self.shared_of, color_idx))

  if not ?self.edit_deltas:
    return

  for key, delta_seq in self.edit_deltas:
    if key.id != self.unit_id or not ?delta_seq:
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
            (VoxelKind(kind_ord), resolve_color(self.shared_of, color_idx))

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
        let color = resolve_color(self.shared_of, color_idx)
        let kind = VoxelKind(kind_ord)
        self.local_voxels[chunk_id][world_pos] = (kind, color)
        if kind != HOLE:
          inc self.block_count

proc unload_chunk*(self: VoxelStore, chunk_id: Vector3) =
  ## Drop a paged-out chunk's local state (the voxel paging counterpart of
  ## apply_snapshot). The data still exists on the authority; a later
  ## `request` re-applies it.
  if chunk_id in self.local_voxels:
    for pos, info in self.local_voxels[chunk_id]:
      if info.kind != HOLE:
        dec self.block_count
    self.local_voxels.del(chunk_id)
  self.pending_chunks.del(chunk_id)

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

proc pack_frame*(self: VoxelStore): FrameData =
  ## Snapshot the current voxel state as one animation frame — every
  ## non-empty chunk, packed with the standard codecs.
  for chunk_id in self.local_voxels.keys:
    let packed = encode_chunk(self.build_chunk_state(chunk_id))
    if not packed.is_empty:
      result.chunks[chunk_id] = packed

proc load_frame*(self: VoxelStore, frame: FrameData) =
  ## Replace the live voxel state with a frame's contents — the authoring
  ## path (re-edit a saved pose). Goes through the synced chunk tables, so
  ## every side re-renders it like any other voxel change.
  let stale = self.local_voxels.keys.to_seq
  for chunk_id in stale:
    if chunk_id notin frame.chunks:
      if chunk_id in self.packed_chunks:
        self.packed_chunks.del(chunk_id)
      if chunk_id in self.chunk_deltas:
        self.chunk_deltas.del(chunk_id)
      for pos, info in self.local_voxels[chunk_id]:
        if info.kind != HOLE:
          dec self.block_count
      self.local_voxels.del(chunk_id)
  for chunk_id, packed in frame.chunks:
    self.apply_snapshot(chunk_id, packed)
    self.packed_chunks[chunk_id] = packed
    if chunk_id in self.chunk_deltas:
      self.chunk_deltas[chunk_id].clear
  self.pending_chunks.clear

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

iterator all_voxels*(self: VoxelStore): tuple[pos: Vector3, info: VoxelInfo] =
  for chunk_id, chunk in self.local_voxels:
    for pos, info in chunk:
      yield (pos, info)

proc chunk_aabb(chunk_id: Vector3): AABB {.inline.} =
  init_aabb(chunk_id * ChunkDim, vec3(ChunkDim, ChunkDim, ChunkDim))

type SlotCache = Table[int, int64]
  ## Per-render-call memo: a chunk has at most a few dozen distinct colors,
  ## but thousands of voxels — resolving each index once keeps the resolver
  ## (palette read + registry lookup) off the per-voxel path.

proc library_slot(
    resolver: ColorIndexResolver, color_idx: int, cache: var SlotCache
): int64 {.inline.} =
  ## The engine voxel type id for a packed color index. Named colors are
  ## their own library slots; static palette indices need the resolver.
  if color_idx < STATIC_COLOR_BASE or resolver.is_nil:
    return color_idx.int64
  cache.with_value(color_idx, slot):
    return slot[]
  result = resolver(color_idx)
  cache[color_idx] = result

proc render_snapshot_direct*(
    voxel_tool: VoxelTool,
    chunk_id: Vector3,
    snapshot: SnapshotData,
    resolver: ColorIndexResolver = nil,
): int {.discardable.} =
  ## Render a chunk's snapshot into the terrain. Checks
  ## `is_area_editable` first: if the chunk's data block is fully
  ## loaded we use the cheap per-voxel `set_voxel`; otherwise we fall
  ## back to a one-chunk `paste`, because `set_voxel` silently no-ops
  ## for chunks the terrain hasn't fully loaded yet.
  if snapshot.data.len == 0:
    return 0
  let voxels = decode_chunk(snapshot)
  let chunk_min = chunk_id * ChunkDim
  var slot_cache: SlotCache
  if voxel_tool.is_area_editable(chunk_aabb(chunk_id)):
    for linear in 0 ..< CHUNK_VOLUME:
      let packed_voxel = voxels[linear]
      if packed_voxel != EMPTY_VOXEL:
        let local_pos = from_linear(linear)
        let (color_idx, _) = unpack_voxel(packed_voxel)
        voxel_tool.set_voxel(
          chunk_min + local_pos,
          resolver.library_slot(color_idx, slot_cache),
        )
        inc result
  else:
    let buffer = gdnew[VoxelBuffer]()
    buffer.create(ChunkDim, ChunkDim, ChunkDim)
    buffer.fill(0)
    for linear in 0 ..< CHUNK_VOLUME:
      let packed_voxel = voxels[linear]
      if packed_voxel != EMPTY_VOXEL:
        let local_pos = from_linear(linear)
        let (color_idx, _) = unpack_voxel(packed_voxel)
        buffer.set_voxel(
          resolver.library_slot(color_idx, slot_cache),
          local_pos.x.int64, local_pos.y.int64, local_pos.z.int64,
        )
        inc result
    voxel_tool.paste(chunk_min, buffer, 1, 0)

proc render_snapshot_replace*(
    voxel_tool: VoxelTool,
    chunk_id: Vector3,
    snapshot: SnapshotData,
    resolver: ColorIndexResolver = nil,
): int {.discardable.} =
  ## Render a chunk snapshot REPLACING whatever the chunk showed before —
  ## cells empty in the snapshot are cleared. Always paste-based, because
  ## paste overwrites every cell; the additive fast path in
  ## render_snapshot_direct leaves stale voxels behind (frame flips need
  ## replacement semantics).
  let voxels = decode_chunk(snapshot)
  let chunk_min = chunk_id * ChunkDim
  var slot_cache: SlotCache
  let buffer = gdnew[VoxelBuffer]()
  buffer.create(ChunkDim, ChunkDim, ChunkDim)
  buffer.fill(0)
  for linear in 0 ..< CHUNK_VOLUME:
    let packed_voxel = voxels[linear]
    if packed_voxel != EMPTY_VOXEL:
      let local_pos = from_linear(linear)
      let (color_idx, _) = unpack_voxel(packed_voxel)
      buffer.set_voxel(
        resolver.library_slot(color_idx, slot_cache),
        local_pos.x.int64, local_pos.y.int64, local_pos.z.int64,
      )
      inc result
  voxel_tool.paste(chunk_min, buffer, 1, 0)

proc render_delta_direct*(
    voxel_tool: VoxelTool,
    chunk_id: Vector3,
    delta: DeltaUpdate,
    resolver: ColorIndexResolver = nil,
): int {.discardable.} =
  ## Render a delta into the terrain. Same fast/slow split as
  ## render_snapshot_direct — `set_voxel` for editable chunks, `paste`
  ## fallback for chunks the terrain doesn't yet consider fully
  ## loaded (where `set_voxel` would silently drop the write).
  if delta.data.len == 0:
    return 0
  let changes = decode_delta(delta)
  let chunk_min = chunk_id * ChunkDim
  var slot_cache: SlotCache
  let editable = voxel_tool.is_area_editable(chunk_aabb(chunk_id))
  if editable:
    for (local_pos, packed_voxel) in changes:
      let world_pos = chunk_min + local_pos
      if packed_voxel == EMPTY_VOXEL:
        voxel_tool.set_voxel(world_pos, 0)
      else:
        let (color_idx, _) = unpack_voxel(packed_voxel)
        voxel_tool.set_voxel(
          world_pos, resolver.library_slot(color_idx, slot_cache)
        )
      inc result
  else:
    let buffer = gdnew[VoxelBuffer]()
    buffer.create(ChunkDim, ChunkDim, ChunkDim)
    buffer.fill(0)
    for (local_pos, packed_voxel) in changes:
      if packed_voxel == EMPTY_VOXEL:
        # paste with use_mask=true treats 0 as skip, so eraser writes
        # need to go through set_voxel separately. Best-effort; if the
        # area isn't editable, the eraser won't take effect until a
        # later render pass.
        voxel_tool.set_voxel(chunk_min + local_pos, 0)
      else:
        let (color_idx, _) = unpack_voxel(packed_voxel)
        buffer.set_voxel(
          resolver.library_slot(color_idx, slot_cache),
          local_pos.x.int64, local_pos.y.int64, local_pos.z.int64,
        )
        inc result
    voxel_tool.paste(chunk_min, buffer, 1, 0)

proc erase_chunk_direct*(voxel_tool: VoxelTool, chunk_id: Vector3) =
  ## Clear a paged-out chunk from the terrain — the un-render counterpart of
  ## render_snapshot_direct. One zero-filled paste: the godot_voxel paste
  ## binding overwrites every cell (no use_mask — see ensure_buffer), which is
  ## exactly what an eraser wants, and it works whether or not the terrain
  ## considers the chunk editable.
  let chunk_min = chunk_id * ChunkDim
  let buffer = gdnew[VoxelBuffer]()
  buffer.create(ChunkDim, ChunkDim, ChunkDim)
  buffer.fill(0)
  voxel_tool.paste(chunk_min, buffer, 1, 0)

const ASAP_PASTE_INTERVAL = init_duration(seconds = 2)

proc init*(
    _: type VoxelRenderer,
    voxel_tool: VoxelTool,
    resolver: ColorIndexResolver = nil,
): VoxelRenderer =
  assert ?voxel_tool
  VoxelRenderer(voxel_tool: voxel_tool, resolver: resolver)

proc ensure_buffer(self: VoxelRenderer, chunk_id: Vector3) =
  let chunk_min = chunk_id * ChunkDim
  let chunk_max = chunk_min + vec3(ChunkDim - 1, ChunkDim - 1, ChunkDim - 1)

  if not ?self.buffer:
    self.min_pos = chunk_min
    self.max_pos = chunk_max
    self.buffer_size = vec3(ChunkDim, ChunkDim, ChunkDim)
    self.buffer = gdnew[VoxelBuffer]()
    self.buffer.create(ChunkDim, ChunkDim, ChunkDim)
    # Zero first — VoxelBuffer.create doesn't initialize cells, so any
    # cells voxel_tool.copy below doesn't touch would otherwise hold
    # uninitialized memory and get pasted back as spurious voxels.
    self.buffer.fill(0)
    # Pre-populate the buffer with the terrain's current state so the
    # paste at end_asap doesn't wipe voxels that were written before
    # ASAP began. (The godot_voxel paste binding doesn't expose
    # use_mask, so paste always overwrites every cell including the
    # untouched ones — pre-populating means "untouched" cells already
    # hold the correct existing values.)
    self.voxel_tool.copy(self.min_pos, self.buffer, 1)
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
    # Zero first; see note above in the fresh-buffer path.
    new_buffer.fill(0)
    # Pre-populate the new buffer's terrain region from the terrain,
    # then overlay our existing buffer's contents (which carry the
    # in-flight deltas) on top.
    self.voxel_tool.copy(new_min, new_buffer, 1)

    let offset = self.min_pos - new_min
    new_buffer.copy_channel_from_area(
      self.buffer, vec3(0, 0, 0), self.buffer_size, offset, 0
    )

    self.buffer = new_buffer
    self.min_pos = new_min
    self.max_pos = new_max
    self.buffer_size = new_size

proc buffer_snapshot*(
    self: VoxelRenderer,
    chunk_id: Vector3,
    snapshot: SnapshotData,
    replace = false,
): int {.discardable.} =
  ## Write a chunk snapshot into the ASAP buffer. With `replace`, the
  ## chunk's whole region is zeroed first: a REWRITTEN chunk (cleared and
  ## redrawn in one sync batch) must not inherit voxels the new content
  ## doesn't cover — the buffer is pre-populated from the terrain, so
  ## additive writes would resurrect them.
  if snapshot.data.len == 0:
    return
  self.ensure_buffer(chunk_id)
  if replace:
    let chunk_min = chunk_id * ChunkDim
    for x in 0 ..< ChunkDim:
      for y in 0 ..< ChunkDim:
        for z in 0 ..< ChunkDim:
          let buffer_pos = chunk_min + vec3(x.float, y.float, z.float) -
            self.min_pos
          self.buffer.set_voxel(
            0, buffer_pos.x.int64, buffer_pos.y.int64, buffer_pos.z.int64
          )
  var slot_cache: SlotCache
  let voxels = decode_chunk(snapshot)
  for linear in 0 ..< CHUNK_VOLUME:
    let packed_voxel = voxels[linear]
    if packed_voxel != EMPTY_VOXEL:
      let local_pos = from_linear(linear)
      let world_pos = chunk_id * ChunkDim + local_pos
      let buffer_pos = world_pos - self.min_pos
      let (color_idx, _) = unpack_voxel(packed_voxel)
      self.buffer.set_voxel(
        self.resolver.library_slot(color_idx, slot_cache), buffer_pos.x.int64,
        buffer_pos.y.int64, buffer_pos.z.int64,
      )
      inc result
  self.dirty = true

proc buffer_delta*(
    self: VoxelRenderer, chunk_id: Vector3, delta: DeltaUpdate
): int {.discardable.} =
  if delta.data.len == 0:
    return
  self.ensure_buffer(chunk_id)
  var slot_cache: SlotCache
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
        self.resolver.library_slot(color_idx, slot_cache), buffer_pos.x.int64,
        buffer_pos.y.int64, buffer_pos.z.int64,
      )
      inc result
  self.dirty = true

proc begin_asap*(self: VoxelRenderer) =
  # If a previous cycle's buffer wasn't pasted yet, paste it now
  # before clearing. Defensive: keeps the renderer robust against
  # rapid ASAP toggling.
  if ?self.buffer and self.dirty:
    self.voxel_tool.paste(self.min_pos, self.buffer, 1, 0)
  self.buffer = nil
  self.min_pos = vec3()
  self.max_pos = vec3()
  self.buffer_size = vec3()
  self.dirty = false
  self.asap_active = true
  # Backdate so the first dirty buffer paints on the next tick instead of
  # waiting a full interval — the initial draw shows immediately, then
  # sustained drawing batches at ASAP_PASTE_INTERVAL.
  self.last_paste_time = get_mono_time() - ASAP_PASTE_INTERVAL

proc tick*(self: VoxelRenderer, is_local: bool) =
  ## Periodic paste for local ASAP mode only (visual progress feedback).
  ## Remote ASAP buffers without periodic paste - final paste via end_asap().
  if self.asap_active and is_local:
    let now = get_mono_time()
    let elapsed = now - self.last_paste_time
    if elapsed >= ASAP_PASTE_INTERVAL and ?self.buffer and self.dirty:
      # The clock only advances when something pastes: an empty tick must
      # not consume begin_asap's backdate, or the run's first content ends
      # up waiting for end_asap — recognized a full sleep-park after the
      # script finishes drawing — instead of pasting on arrival.
      self.voxel_tool.paste(self.min_pos, self.buffer, 1, 0)
      self.dirty = false
      self.last_paste_time = now

proc end_asap*(self: VoxelRenderer) =
  if ?self.buffer and self.dirty:
    self.voxel_tool.paste(self.min_pos, self.buffer, 1, 0)
  self.buffer = nil
  self.min_pos = vec3()
  self.max_pos = vec3()
  self.buffer_size = vec3()
  self.dirty = false
  self.asap_active = false
