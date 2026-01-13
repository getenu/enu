## VoxelStore - Extracted voxel management for Build
##
## This module handles voxel storage, network synchronization (packed chunks),
## and batching. It can be tested independently of Build.

import std/[tables, sets, math, strformat]
import pkg/model_citizen
import core
import models/[packed_chunks, colors]

const
  ChunkSize* = vec3(16, 16, 16)
  MAX_BLOCK_COUNT* = 100_000
  MAX_DELTA_UPDATES* = 100 # Force snapshot after this many deltas
  MAX_CHANGES_PER_DELTA* = 100
    # Force snapshot if single update has this many changes
  DEFAULT_SNAPSHOTS_PER_FRAME* = 2 # Per-build default
  DEFAULT_GLOBAL_SNAPSHOTS* = 32 # Global default across all builds

# VoxelStore type is defined in types.nim

proc buffer*(position: Vector3): Vector3 =
  (position / ChunkSize).floor

proc chunk_to_local*(chunk_id: Vector3, pos: Vector3): int =
  ## Convert world position to linear index within chunk
  let local_x = int(pos.x - chunk_id.x * 16) mod 16
  let local_y = int(pos.y - chunk_id.y * 16) mod 16
  let local_z = int(pos.z - chunk_id.z * 16) mod 16
  linear_position(local_x, local_y, local_z)

proc create_chunk*(self: VoxelStore): Chunk =
  let flags =
    if self.disable_packed:
      {SyncLocal, SyncRemote}
    else:
      {}
  Chunk.init(ctx = self.ctx, flags = flags)

proc init*(
    _: type VoxelStore,
    id: string,
    ctx: ZenContext = nil,
    disable_packed: bool = false,
): VoxelStore =
  ## Initialize a VoxelStore.
  ## disable_packed: If true, chunks sync directly (no packed format).
  let chunk_flags =
    if disable_packed:
      {SyncLocal, SyncRemote}
    else:
      {} # No sync - reconstructed from packed_chunks/chunk_deltas

  # Use provided context or fall back to thread context
  let use_ctx = if ctx.isNil: Zen.thread_ctx else: ctx

  result = VoxelStore(
    id: id,
    disable_packed: disable_packed,
    ctx: use_ctx,
    chunks: ZenTable[Vector3, Chunk].init(
      id = id & ".chunks", ctx = use_ctx, flags = chunk_flags
    ),
    packed_chunks: ZenTable[Vector3, SnapshotData].init(
      id = id & ".packed_chunks", ctx = use_ctx, flags = {SyncLocal, SyncRemote}
    ),
    chunk_deltas: ZenTable[Vector3, ZenSeq[DeltaUpdate]].init(
      id = id & ".chunk_deltas", ctx = use_ctx, flags = {SyncLocal, SyncRemote}
    ),
  )

proc verify_block_count*(self: VoxelStore) =
  var actual_count = 0
  for chunk_id, chunk in self.chunks:
    for position, info in chunk:
      if info.kind != Hole:
        inc actual_count

  if actual_count != self.block_count:
    raise_assert &"Block count mismatch for {self.id}: counter={self.block_count}, actual={actual_count}"

proc contains*(self: VoxelStore, position: Vector3): bool =
  let buf = position.buffer
  # Check both committed chunks and batched voxels
  if buf in self.chunks and position in self.chunks[buf]:
    return true
  if self.batching and buf in self.batched_voxels and
      position in self.batched_voxels[buf]:
    return true

proc voxel_info*(self: VoxelStore, position: Vector3): VoxelInfo =
  let buf = position.buffer
  # Check batched voxels first (they may override committed chunks)
  if self.batching and buf in self.batched_voxels and
      position in self.batched_voxels[buf]:
    return self.batched_voxels[buf][position]
  self.chunks[buf][position]

proc find_voxel*(self: VoxelStore, position: Vector3): Option[VoxelInfo] =
  let buf = position.buffer
  # Check batched voxels first
  if self.batching and buf in self.batched_voxels and
      position in self.batched_voxels[buf]:
    return some(self.batched_voxels[buf][position])
  if buf in self.chunks and position in self.chunks[buf]:
    return some(self.chunks[buf][position])
  none(VoxelInfo)

proc add_voxel*(self: VoxelStore, position: Vector3, voxel: VoxelInfo) =
  ## Add a voxel to the store.
  let buffer = position.buffer

  if buffer notin self.chunks:
    self.chunks[buffer] = self.create_chunk()
    if self.on_chunk_created != nil:
      self.on_chunk_created(buffer)

  if not self.disable_packed:
    self.dirty_chunks.incl(buffer)
    # Track change for delta encoding (skip if chunk already queued for snapshot)
    if buffer notin self.snapshot_queue:
      let packed = pack_voxel(voxel.color.action_index.ord, voxel.kind.ord)

      self.pending_changes.mgetOrPut(buffer, initTable[Vector3, PackedVoxel]())[
        position
      ] = packed

  # Check if voxel exists in either current chunks or batched voxels
  let exists_in_chunks = position in self.chunks[buffer]
  let exists_in_batched =
    self.batching and buffer in self.batched_voxels and
    position in self.batched_voxels[buffer]

  if self.batching:
    if position notin self.chunks[buffer] or
        self.chunks[buffer][position] != voxel:
      if buffer notin self.batched_voxels:
        self.batched_voxels[buffer] = init_table[Vector3, VoxelInfo]()

      # Check limit before adding new voxel
      if not exists_in_chunks and not exists_in_batched:
        if self.block_count >= MAX_BLOCK_COUNT:
          raise (ref ResourceLimitError)(
            msg:
              &"{self.id}: Block limit exceeded ({MAX_BLOCK_COUNT} blocks maximum)"
          )
        inc self.block_count
        when defined(debug):
          if self.block_count mod CHECK_INTERVAL == 0:
            self.verify_block_count()

      self.batched_voxels[buffer][position] = voxel
  else:
    if not exists_in_chunks:
      if self.block_count >= MAX_BLOCK_COUNT:
        raise (ref ResourceLimitError)(
          msg:
            &"{self.id}: Block limit exceeded ({MAX_BLOCK_COUNT} blocks maximum)"
        )
      inc self.block_count
      when defined(debug):
        if self.block_count mod CHECK_INTERVAL == 0:
          self.verify_block_count()
    self.chunks[buffer][position] = voxel

proc del_voxel*(self: VoxelStore, position: Vector3) =
  ## Remove a voxel from the store.
  let buffer = position.buffer
  if buffer in self.chunks and position in self.chunks[buffer]:
    dec self.block_count
    if not self.disable_packed:
      self.dirty_chunks.incl(buffer)
      # Track deletion as EMPTY_VOXEL (skip if chunk already queued for snapshot)
      if buffer notin self.snapshot_queue:
        self.pending_changes.mgetOrPut(
          buffer, initTable[Vector3, PackedVoxel]()
        )[position] = EMPTY_VOXEL
  self.chunks[buffer].del position

proc batch_changes*(self: VoxelStore): bool =
  ## Start batching mode. Returns true if batching was started.
  if not self.batching:
    self.batching = true
    result = true

proc get_or_create_delta_seq(
    self: VoxelStore, chunk_id: Vector3
): ZenSeq[DeltaUpdate] =
  ## Get existing delta seq or create a new one for the chunk.
  if chunk_id in self.chunk_deltas:
    result = self.chunk_deltas[chunk_id]
  else:
    result = ZenSeq[DeltaUpdate].init(flags = {SyncLocal, SyncRemote})
    self.chunk_deltas[chunk_id] = result

proc build_chunk_state(
    self: VoxelStore, chunk_id: Vector3
): tuple[
  voxels: array[CHUNK_VOLUME, PackedVoxel], current: Table[Vector3, PackedVoxel]
] =
  ## Build voxel state arrays for a chunk.
  if chunk_id in self.chunks:
    let chunk_value = self.chunks[chunk_id].value
    for pos, info in chunk_value:
      let linear = chunk_to_local(chunk_id, pos)
      let color_idx = info.color.action_index.ord
      let kind_ord = info.kind.ord
      let packed = pack_voxel(color_idx, kind_ord)
      result.voxels[linear] = packed
      result.current[pos] = packed

proc update_packed_state(
    self: VoxelStore, chunk_id: Vector3, packed: SnapshotData
) =
  ## Update packed_chunks and chunk_deltas after encoding a snapshot.
  if packed.is_empty:
    if chunk_id in self.packed_chunks:
      self.packed_chunks.del(chunk_id)
    if chunk_id in self.chunk_deltas:
      self.chunk_deltas.del(chunk_id)
  else:
    self.packed_chunks[chunk_id] = packed
    self.content_bytes += packed.data.len
    if chunk_id in self.chunk_deltas:
      self.chunk_deltas[chunk_id].clear

proc flush_delta(
    self: VoxelStore, chunk_id: Vector3, changes: Table[Vector3, PackedVoxel]
) =
  ## Encode and send a delta update. Very cheap - no chunk rebuild.
  if changes.len == 0:
    return

  # Convert to local positions for encoding
  var local_changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]]
  for world_pos, packed in changes:
    let local_pos = vec3(
      floor_mod(world_pos.x.int, 16).float,
      floor_mod(world_pos.y.int, 16).float,
      floor_mod(world_pos.z.int, 16).float,
    )
    local_changes.add (local_pos, packed)

  let delta = encode_delta(local_changes)
  self.content_bytes += delta.data.len
  self.get_or_create_delta_seq(chunk_id).add delta

  # Clear tracked changes
  self.pending_changes.del(chunk_id)

  # Notify for rendering
  if self.on_chunk_flushed != nil:
    self.on_chunk_flushed(chunk_id)

proc queue_dirty_chunks*(self: VoxelStore) =
  ## Categorize dirty chunks into deltas (immediate) vs snapshots (queued).
  ## Deltas are sent immediately. Snapshots are queued for rate-limited processing.
  for chunk_id in self.dirty_chunks:
    let changes = self.pending_changes.getOrDefault(chunk_id)
    let changes_count = changes.len
    let delta_count =
      if chunk_id in self.chunk_deltas:
        self.chunk_deltas[chunk_id].len
      else:
        0
    let had_snapshot = chunk_id in self.packed_chunks

    # Check if chunk is empty
    let chunk_empty =
      chunk_id notin self.chunks or self.chunks[chunk_id].value.len == 0

    let use_snapshot =
      delta_count >= MAX_DELTA_UPDATES or changes_count >= MAX_CHANGES_PER_DELTA or
      not had_snapshot or chunk_empty

    if use_snapshot:
      # Queue for rate-limited processing
      self.snapshot_queue.incl(chunk_id)
    else:
      # Send delta immediately (cheap - no rebuild needed)
      self.flush_delta(chunk_id, changes)

  self.dirty_chunks.clear

proc flush_next_snapshots*(self: VoxelStore, max_count: int): int =
  ## Process up to max_count snapshots from queue. Returns count processed.
  var flushed = 0
  var to_remove: seq[Vector3]

  for chunk_id in self.snapshot_queue:
    if flushed >= max_count:
      break

    # Build full chunk state and encode as snapshot
    let (voxels, _) = self.build_chunk_state(chunk_id)
    let packed = encode_chunk(voxels)
    self.update_packed_state(chunk_id, packed)

    # Clear tracked changes for this chunk
    self.pending_changes.del(chunk_id)

    # Notify for rendering
    if self.on_chunk_flushed != nil:
      self.on_chunk_flushed(chunk_id)

    to_remove.add(chunk_id)
    inc flushed

  for chunk_id in to_remove:
    self.snapshot_queue.excl(chunk_id)

  result = flushed

proc is_flushing*(self: VoxelStore): bool =
  ## Returns true if there are snapshots queued for processing.
  self.snapshot_queue.len > 0

proc apply_changes*(self: VoxelStore, disable_packed: bool = false) =
  ## Flush batched changes to chunks and queue for network sync.
  if self.batching:
    for buffer, chunk in self.batched_voxels:
      self.chunks[buffer] += chunk

    self.batched_voxels.clear
    self.batching = false

  # Queue dirty chunks (deltas sent immediately, snapshots queued)
  if not disable_packed and not self.defer_flush and self.dirty_chunks.len > 0:
    self.queue_dirty_chunks()

proc apply_delta_update*(
    self: VoxelStore, chunk_id: Vector3, delta: DeltaUpdate
) =
  ## Apply a delta update to local chunks (for network receive).
  ## Does NOT mark chunk as dirty since this is receiving data, not generating it.
  let changes = decode_delta(delta)

  for (local_pos, packed_voxel) in changes:
    let world_pos = vec3(
      chunk_id.x * 16 + local_pos.x,
      chunk_id.y * 16 + local_pos.y,
      chunk_id.z * 16 + local_pos.z,
    )

    if packed_voxel == EMPTY_VOXEL:
      # Remove voxel
      if chunk_id in self.chunks and world_pos in self.chunks[chunk_id]:
        let info = self.chunks[chunk_id][world_pos]
        if info.kind != Hole:
          dec self.block_count
        self.chunks[chunk_id].del(world_pos)
    else:
      # Add/modify voxel
      let (color_idx, kind_ord) = unpack_voxel(packed_voxel)
      let color = action_colors[Colors(color_idx)]
      let kind = VoxelKind(kind_ord)

      # Ensure chunk exists
      if chunk_id notin self.chunks:
        self.chunks[chunk_id] = self.create_chunk()
        if self.on_chunk_created != nil:
          self.on_chunk_created(chunk_id)

      # Check if replacing existing voxel
      let existed = world_pos in self.chunks[chunk_id]
      if existed:
        let old_info = self.chunks[chunk_id][world_pos]
        if old_info.kind != Hole:
          dec self.block_count

      self.chunks[chunk_id][world_pos] = (kind, color)
      if kind != Hole:
        inc self.block_count

proc apply_snapshot*(
    self: VoxelStore, chunk_id: Vector3, snapshot: SnapshotData
) =
  ## Decode a snapshot and apply to local chunks (for network receive).
  ## Does NOT mark chunk as dirty since this is receiving data, not generating it.
  if snapshot.data.len == 0:
    return

  let voxels = decode_chunk(snapshot)

  # Clear existing chunk if present
  if chunk_id in self.chunks:
    let chunk = self.chunks[chunk_id]
    for pos, info in chunk:
      if info.kind != Hole:
        dec self.block_count
    self.chunks.del(chunk_id)
    chunk.destroy

  # Check if the packed chunk has any voxels
  var has_voxels = false
  for v in voxels:
    if v != EMPTY_VOXEL:
      has_voxels = true
      break

  if has_voxels:
    self.chunks[chunk_id] = self.create_chunk()
    if self.on_chunk_created != nil:
      self.on_chunk_created(chunk_id)

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
        let color = action_colors[Colors(color_idx)]
        let kind = VoxelKind(kind_ord)
        self.chunks[chunk_id][world_pos] = (kind, color)
        if kind != Hole:
          inc self.block_count

proc apply_chunk_with_deltas*(self: VoxelStore, chunk_id: Vector3) =
  ## Apply snapshot and any existing deltas for a chunk.
  ## Used when a new chunk is first synced from network.
  if chunk_id in self.packed_chunks:
    self.apply_snapshot(chunk_id, self.packed_chunks[chunk_id])

  # Apply any deltas that arrived with the chunk
  if chunk_id in self.chunk_deltas:
    for delta in self.chunk_deltas[chunk_id]:
      self.apply_delta_update(chunk_id, delta)

proc clear_chunk_internal(self: VoxelStore, chunk_id: Vector3) =
  ## Clear a chunk without marking dirty (internal helper).
  if chunk_id in self.chunks:
    let chunk = self.chunks[chunk_id]
    for pos, info in chunk:
      if info.kind != Hole:
        dec self.block_count
    self.chunks.del(chunk_id)
    chunk.destroy

proc clear_chunk*(self: VoxelStore, chunk_id: Vector3) =
  ## Efficiently clear an entire chunk by deleting it from the table.
  ## This sends a single Unassign message instead of many individual voxel deletes.
  self.clear_chunk_internal(chunk_id)
  if not self.disable_packed:
    self.dirty_chunks.incl(chunk_id)

proc clear_chunk_remote*(self: VoxelStore, chunk_id: Vector3) =
  ## Clear a chunk that was removed remotely.
  ## Does NOT mark dirty since this is receiving data, not generating it.
  self.clear_chunk_internal(chunk_id)

proc clear*(self: VoxelStore) =
  ## Clear all voxels from the store.
  let chunks = self.chunks.value
  for chunk_id, chunk in chunks:
    self.chunks.del(chunk_id)
    chunk.destroy

  if not self.disable_packed:
    let packed = self.packed_chunks.value
    for chunk_id in packed.keys:
      self.packed_chunks.del(chunk_id)
    let deltas = self.chunk_deltas.value
    for chunk_id in deltas.keys:
      self.chunk_deltas.del(chunk_id)
    self.pending_changes.clear
    self.snapshot_queue.clear
    self.dirty_chunks.clear

  self.block_count = 0

proc verify_packed_chunks*(self: VoxelStore) =
  ## Verify that packed_chunks + chunk_deltas can reconstruct actual chunks.
  ## Raises an exception with details if there's a mismatch.
  # Collect all chunk_ids from actual chunks, snapshots, and deltas
  var all_chunk_ids: HashSet[Vector3]
  for chunk_id in self.chunks.value.keys:
    all_chunk_ids.incl(chunk_id)
  for chunk_id in self.packed_chunks.value.keys:
    all_chunk_ids.incl(chunk_id)
  for chunk_id in self.chunk_deltas.value.keys:
    all_chunk_ids.incl(chunk_id)

  for chunk_id in all_chunk_ids:
    # Reconstruct chunk from snapshot + deltas
    var reconstructed: Table[Vector3, PackedVoxel]

    # Start with snapshot if exists
    if chunk_id in self.packed_chunks:
      let snapshot = self.packed_chunks[chunk_id]
      if snapshot.data.len > 0:
        let voxels = decode_chunk(snapshot)
        for linear in 0 ..< CHUNK_VOLUME:
          if voxels[linear] != EMPTY_VOXEL:
            let local_pos = from_linear(linear)
            let world_pos = vec3(
              chunk_id.x * 16 + local_pos.x,
              chunk_id.y * 16 + local_pos.y,
              chunk_id.z * 16 + local_pos.z,
            )
            reconstructed[world_pos] = voxels[linear]

    # Apply all deltas for this chunk
    if chunk_id in self.chunk_deltas:
      for delta in self.chunk_deltas[chunk_id]:
        let changes = decode_delta(delta)
        for (local_pos, packed_voxel) in changes:
          let world_pos = vec3(
            chunk_id.x * 16 + local_pos.x,
            chunk_id.y * 16 + local_pos.y,
            chunk_id.z * 16 + local_pos.z,
          )
          if packed_voxel == EMPTY_VOXEL:
            reconstructed.del(world_pos)
          else:
            reconstructed[world_pos] = packed_voxel

    # Build actual chunk state
    var actual: Table[Vector3, PackedVoxel]
    if chunk_id in self.chunks:
      for pos, info in self.chunks[chunk_id]:
        let color_idx = info.color.action_index.ord
        let kind_ord = info.kind.ord
        let packed = pack_voxel(color_idx, kind_ord)
        actual[pos] = packed

    # Compare reconstructed vs actual
    var mismatches: seq[string]

    # Check for voxels in actual but not in reconstructed
    for pos, packed in actual:
      if pos notin reconstructed:
        let (c, k) = unpack_voxel(packed)
        mismatches.add &"  Missing in reconstructed: {pos} (color={c}, kind={k})"
      elif reconstructed[pos] != packed:
        let (ac, ak) = unpack_voxel(packed)
        let (rc, rk) = unpack_voxel(reconstructed[pos])
        mismatches.add &"  Value mismatch at {pos}: actual=(color={ac}, kind={ak}), reconstructed=(color={rc}, kind={rk})"

    # Check for voxels in reconstructed but not in actual
    for pos, packed in reconstructed:
      if pos notin actual:
        let (c, k) = unpack_voxel(packed)
        mismatches.add &"  Extra in reconstructed: {pos} (color={c}, kind={k})"

    if mismatches.len > 0:
      let has_snapshot = chunk_id in self.packed_chunks
      let delta_count =
        if chunk_id in self.chunk_deltas:
          self.chunk_deltas[chunk_id].len
        else:
          0
      raise newException(
        AssertionDefect,
        &"Packed chunk verification failed for {self.id} chunk {chunk_id}:\n" &
          &"  has_snapshot={has_snapshot}, delta_count={delta_count}\n" &
          &"  actual_voxels={actual.len}, reconstructed_voxels={reconstructed.len}\n" &
          mismatches[0 .. min(mismatches.len - 1, 19)].join("\n"),
      )
