## VoxelStore — a build's per-side voxel state: a lazy read-through cache of
## decoded chunks over the synced tables (packed_chunks / chunk_deltas), plus
## the persisted-edit bookkeeping. Point reads/writes, flushing to the synced
## tables, applying inbound snapshots/deltas, and frame pack/load live here.
import std/[options, tables, monotimes, times, sequtils, sets, hashes]
import pkg/godot except print, Color
import core
import models/colors
import ./codec

proc shared_of(self: VoxelStore): Shared =
  if ?self.build: self.build.shared_value.value else: nil

proc init*(
    _: type VoxelStore,
    ctx: EdContext = nil,
    thing_id: string = "",
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
    thing_id: thing_id,
    build: build,
    edit_snapshots: edit_snapshots,
    edit_deltas: edit_deltas,
    # Main only runs interactive point queries (targeting, floor-follow,
    # draw), so its decoded working set is a small LRU. The worker's scripts,
    # saves and frame packs touch everything -- unbounded (0). A build-less
    # store (tests, tools) is never capped: with no synced tables behind it,
    # its cache is authoritative and eviction would lose data.
    cache_cap:
      if ?build and use_ctx.metrics_label == "main":
        MAIN_CHUNK_CACHE_CAP
      else:
        0,
  )

proc compose_chunk(self: VoxelStore, chunk_id: Vector3): CachedChunk =
  ## A chunk's live cell state, decoded fresh from the synced tables plus the
  ## unflushed write buffer: packed snapshot ⊕ deltas ⊕ pending. This is the
  ## single source of truth the cache and every bulk iterator build on. A
  ## standalone store (no Build — tests, tools) has no synced tables; its
  ## cache is authoritative (see apply_snapshot) and pending is the only
  ## other input.
  result = CachedChunk()
  if ?self.build:
    if chunk_id in self.packed_chunks:
      result.cells = decode_chunk(self.packed_chunks[chunk_id])
    if chunk_id in self.chunk_deltas:
      for delta in self.chunk_deltas[chunk_id]:
        for (local_pos, voxel) in decode_delta(delta):
          result.cells[linear_position(local_pos)] = voxel
  if chunk_id in self.pending_chunks:
    for (local_pos, voxel) in self.pending_chunks[chunk_id]:
      result.cells[linear_position(local_pos)] = voxel
  for v in result.cells:
    if v != EMPTY_VOXEL:
      inc result.count

proc cached_chunk(self: VoxelStore, chunk_id: Vector3): CachedChunk =
  ## The chunk's decoded cells for point reads and writes: cache hit or
  ## compose-and-insert, evicting the least recently touched entry when the
  ## side's cap is exceeded (main only; the worker is unbounded).
  inc self.cache_tick
  self.chunk_cache.with_value(chunk_id, entry):
    entry[].tick = self.cache_tick
    return entry[]
  result = self.compose_chunk(chunk_id)
  result.tick = self.cache_tick
  if self.cache_cap > 0 and self.chunk_cache.len >= self.cache_cap:
    # Eviction invariant: never evict a chunk with unflushed writes — a
    # recompose reads the synced tables, so anything still in
    # `pending_chunks` would be silently lost. Main flushes every write in
    # the same call today, but that's a cross-file coincidence; enforce it
    # here. If every entry is dirty, skip eviction and run over cap until
    # the next flush.
    var oldest_id: Vector3
    var oldest_tick = int.high
    for id, entry in self.chunk_cache:
      if entry.tick < oldest_tick and id notin self.pending_chunks:
        oldest_tick = entry.tick
        oldest_id = id
    if oldest_tick < int.high:
      self.chunk_cache.del(oldest_id)
  self.chunk_cache[chunk_id] = result

iterator chunk_ids*(self: VoxelStore): Vector3 =
  ## Every chunk that may hold voxels, deduped across the synced tables, the
  ## write buffer, and the cache (which is authoritative on a standalone
  ## store) -- the id set bulk operations walk.
  var seen: HashSet[Vector3]
  if ?self.build:
    for chunk_id in self.packed_chunks.value.keys:
      if not seen.contains_or_incl(chunk_id):
        yield chunk_id
    for chunk_id in self.chunk_deltas.value.keys:
      if not seen.contains_or_incl(chunk_id):
        yield chunk_id
  for chunk_id in self.pending_chunks.keys:
    if not seen.contains_or_incl(chunk_id):
      yield chunk_id
  for chunk_id in self.chunk_cache.keys:
    if not seen.contains_or_incl(chunk_id):
      yield chunk_id

proc peek_chunk(self: VoxelStore, chunk_id: Vector3): CachedChunk =
  ## The chunk's cells without inserting into the cache: bulk iteration uses
  ## this so a whole-build scan can't flush main's hot interactive set.
  self.chunk_cache.with_value(chunk_id, entry):
    return entry[]
  self.compose_chunk(chunk_id)

proc unpack_info(self: VoxelStore, packed: PackedVoxel): VoxelInfo =
  let (color_idx, kind_ord) = unpack_voxel(packed)
  (VoxelKind(kind_ord), resolve_color(self.shared_of, color_idx))

proc contains*(self: VoxelStore, position: Vector3): bool =
  self.cached_chunk(position.buffer).cells[linear_position(position)] !=
    EMPTY_VOXEL

proc voxel_info*(self: VoxelStore, position: Vector3): VoxelInfo =
  self.unpack_info(
    self.cached_chunk(position.buffer).cells[linear_position(position)]
  )

proc find_voxel*(self: VoxelStore, position: Vector3): Option[VoxelInfo] =
  let packed = self.cached_chunk(position.buffer).cells[linear_position(position)]
  if packed != EMPTY_VOXEL:
    some(self.unpack_info(packed))
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
  self.cached_chunk(chunk_id).cells

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
    let chunk_empty = self.cached_chunk(chunk_id).count == 0

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
  let key: EditKey = (self.thing_id, chunk_id)
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
  let key: EditKey = (self.thing_id, chunk_id)
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
    let key: EditKey = (self.thing_id, chunk_id)
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
  let chunk = self.cached_chunk(chunk_id)
  let linear = linear_position(position)

  if chunk.count == 0 and not self.on_chunk_created.is_nil:
    self.on_chunk_created(chunk_id)

  let packed =
    pack_voxel(pack_color_index(self.shared_of, voxel.color), voxel.kind.ord)
  if chunk.cells[linear] == EMPTY_VOXEL:
    inc chunk.count
  chunk.cells[linear] = packed

  let local_pos = vec3(
    floor_mod(position.x.int, 16).float,
    floor_mod(position.y.int, 16).float,
    floor_mod(position.z.int, 16).float,
  )

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

  if voxel.kind == PERSISTED:
    {.cast(gcsafe).}:
      self.set_edit(position, voxel)

proc del_voxel*(self: VoxelStore, position: Vector3) =
  let chunk_id = position.buffer
  let chunk = self.cached_chunk(chunk_id)
  let linear = linear_position(position)
  if chunk.cells[linear] != EMPTY_VOXEL:
    chunk.cells[linear] = EMPTY_VOXEL
    dec chunk.count

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
      let chunk_empty = chunk.count == 0
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
    let key: EditKey = (self.thing_id, chunk_id)
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
      let key: EditKey = (self.thing_id, chunk_id)
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
    if key.id != self.thing_id:
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
    if key.id != self.thing_id or not ?delta_seq:
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
  ## A whole-chunk snapshot arrived (sync watch): the cached decode, if any,
  ## is stale -- drop it and let the next read compose from the new blob.
  ## Nothing decodes until something actually reads the chunk. On a
  ## standalone store (no Build) there is no synced table to re-read, so the
  ## decode installs directly: the cache is the store.
  if snapshot.data.len == 0:
    return
  if ?self.build:
    self.chunk_cache.del(chunk_id)
  else:
    let chunk = CachedChunk(cells: decode_chunk(snapshot))
    for v in chunk.cells:
      if v != EMPTY_VOXEL:
        inc chunk.count
    self.chunk_cache[chunk_id] = chunk

proc unload_chunk*(self: VoxelStore, chunk_id: Vector3) =
  ## Drop a paged-out chunk's local state (the voxel paging counterpart of
  ## apply_snapshot). The data still exists on the authority; a later
  ## `request` re-applies it.
  self.chunk_cache.del(chunk_id)
  self.pending_chunks.del(chunk_id)

proc apply_delta*(self: VoxelStore, chunk_id: Vector3, delta: DeltaUpdate) =
  ## A delta arrived (sync watch): poke a cached decode in place; an uncached
  ## chunk needs nothing -- the next read composes the delta from the table.
  self.chunk_cache.with_value(chunk_id, entry):
    for (local_pos, packed_voxel) in decode_delta(delta):
      let linear = linear_position(local_pos)
      if entry[].cells[linear] != EMPTY_VOXEL:
        dec entry[].count
      if packed_voxel != EMPTY_VOXEL:
        inc entry[].count
      entry[].cells[linear] = packed_voxel

proc pack_frame*(self: VoxelStore): FrameData =
  ## Snapshot the current voxel state as one animation frame — every
  ## non-empty chunk, packed with the standard codecs.
  for chunk_id in self.chunk_ids:
    let chunk = self.peek_chunk(chunk_id)
    if chunk.count > 0:
      let packed = encode_chunk(chunk.cells)
      if not packed.is_empty:
        result.chunks[chunk_id] = packed

proc load_frame*(self: VoxelStore, frame: FrameData) =
  ## Replace the live voxel state with a frame's contents — the authoring
  ## path (re-edit a saved pose). Goes through the synced chunk tables, so
  ## every side re-renders it like any other voxel change.
  let stale = self.chunk_ids.to_seq
  for chunk_id in stale:
    if chunk_id notin frame.chunks:
      if chunk_id in self.packed_chunks:
        self.packed_chunks.del(chunk_id)
      if chunk_id in self.chunk_deltas:
        self.chunk_deltas.del(chunk_id)
      self.chunk_cache.del(chunk_id)
  for chunk_id, packed in frame.chunks:
    self.apply_snapshot(chunk_id, packed)
    self.packed_chunks[chunk_id] = packed
    if chunk_id in self.chunk_deltas:
      self.chunk_deltas[chunk_id].clear
  self.pending_chunks.clear

proc clear*(self: VoxelStore, all = false) =
  self.chunk_cache.clear
  let packed = self.packed_chunks.value
  for chunk_id in packed.keys:
    self.packed_chunks.del(chunk_id)
  let deltas = self.chunk_deltas.value
  for chunk_id in deltas.keys:
    self.chunk_deltas.del(chunk_id)
  self.pending_chunks.clear
  if all:
    # `clear` normally spares the persisted edits (a reset clears the render
    # state and restores from them). Pass all = true when redrawing from
    # scratch and the edits must NOT accumulate — e.g. capturing successive
    # animation frames, where each frame is a fresh full draw.
    let snaps = self.edit_snapshots.value
    for key in snaps.keys:
      self.edit_snapshots.del(key)
    let edeltas = self.edit_deltas.value
    for key in edeltas.keys:
      self.edit_deltas.del(key)
    self.local_edits.clear
    self.pending_edits.clear

iterator all_voxels*(self: VoxelStore): tuple[pos: Vector3, info: VoxelInfo] =
  ## Every voxel with its world position, streaming chunk by chunk. Reads
  ## through `peek_chunk` (no cache insertion) so a whole-build scan can't
  ## flush main's interactive working set.
  for chunk_id in self.chunk_ids.to_seq:
    let chunk = self.peek_chunk(chunk_id)
    if chunk.count == 0:
      continue
    for linear in 0 ..< CHUNK_VOLUME:
      let packed = chunk.cells[linear]
      if packed != EMPTY_VOXEL:
        let pos = from_linear(linear)
        let world_pos = vec3(
          chunk_id.x * ChunkDim.float + pos.x,
          chunk_id.y * ChunkDim.float + pos.y,
          chunk_id.z * ChunkDim.float + pos.z,
        )
        yield (world_pos, self.unpack_info(packed))

