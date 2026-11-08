## VoxelStore — a build's per-side voxel state: a lazy read-through cache of
## decoded chunks over the synced tables (packed_chunks / chunk_deltas), plus
## the persisted-edit bookkeeping. Point reads/writes, flushing to the synced
## tables, applying inbound snapshots/deltas, and per-frame copies live here.
##
## Every row is keyed by frame. Point reads and writes go to `frame_id`, the
## frame this side targets: the frame a script draws into on the worker, the
## frame on screen on main.
import std/[options, tables, monotimes, times, sequtils, sets, hashes]
import pkg/godot except print, Color
import core
import models/colors
import ./codec

proc shared_of(self: VoxelStore): Shared =
  if ?self.build: self.build.shared_value.value else: nil

proc note_chunk*(self: VoxelStore, chunk_id: Vector3) {.inline.} =
  ## This store now holds `chunk_id`. The owner grows the unit's bounds from
  ## it — the terrain clips loading and meshing to those bounds, so a chunk
  ## that never reports here is a chunk that never renders.
  ##
  ## Call it from anywhere a chunk enters the store, unconditionally: it is
  ## idempotent, and a condition on one caller and not another is exactly how
  ## chunks went missing before.
  if not self.on_chunk_created.is_nil:
    self.on_chunk_created(chunk_id)

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
    # saves and frame copies touch everything -- unbounded (0). A build-less
    # store (tests, tools) is never capped: with no synced tables behind it,
    # its cache is authoritative and eviction would lose data.
    cache_cap:
      if ?build and use_ctx.metrics_label == "main":
        MAIN_CHUNK_CACHE_CAP
      else:
        0,
  )

proc key(self: VoxelStore, chunk_id: Vector3): FrameChunk {.inline.} =
  (self.frame_id, chunk_id)

proc edit_key(self: VoxelStore, fc: FrameChunk): EditKey {.inline.} =
  (self.thing_id, fc.frame, fc.loc)

template with_frame*(self: VoxelStore, id: int, body: untyped) =
  ## Run `body` with the store targeting frame `id`.
  let previous = self.frame_id
  self.frame_id = id
  try:
    body
  finally:
    self.frame_id = previous

proc compose_chunk(self: VoxelStore, fc: FrameChunk): CachedChunk =
  ## A chunk's live cell state, decoded fresh from the synced tables plus the
  ## unflushed write buffer: packed snapshot ⊕ deltas ⊕ pending. This is the
  ## single source of truth the cache and every bulk iterator build on. A
  ## standalone store (no Build — tests, tools) has no synced tables; its
  ## cache is authoritative (see apply_snapshot) and pending is the only
  ## other input.
  result = CachedChunk()
  if ?self.build:
    if fc in self.packed_chunks:
      result.cells = decode_chunk(self.packed_chunks[fc])
    if fc in self.chunk_deltas:
      for delta in self.chunk_deltas[fc]:
        for (local_pos, voxel) in decode_delta(delta):
          result.cells[linear_position(local_pos)] = voxel
  if fc in self.pending_chunks:
    for (local_pos, voxel) in self.pending_chunks[fc]:
      result.cells[linear_position(local_pos)] = voxel
  for v in result.cells:
    if v != EMPTY_VOXEL:
      inc result.count

proc cached_chunk(self: VoxelStore, fc: FrameChunk): CachedChunk =
  ## The chunk's decoded cells for point reads and writes: cache hit or
  ## compose-and-insert, evicting the least recently touched entry when the
  ## side's cap is exceeded (main only; the worker is unbounded).
  inc self.cache_tick
  self.chunk_cache.with_value(fc, entry):
    entry[].tick = self.cache_tick
    return entry[]
  result = self.compose_chunk(fc)
  result.tick = self.cache_tick
  if self.cache_cap > 0 and self.chunk_cache.len >= self.cache_cap:
    # Eviction invariant: never evict a chunk with unflushed writes — a
    # recompose reads the synced tables, so anything still in
    # `pending_chunks` would be silently lost. Main flushes every write in
    # the same call today, but that's a cross-file coincidence; enforce it
    # here. If every entry is dirty, skip eviction and run over cap until
    # the next flush.
    var oldest_id: FrameChunk
    var oldest_tick = int.high
    for id, entry in self.chunk_cache:
      if entry.tick < oldest_tick and id notin self.pending_chunks and
          id notin self.pending_snapshots:
        oldest_tick = entry.tick
        oldest_id = id
    if oldest_tick < int.high:
      self.chunk_cache.del(oldest_id)
  self.chunk_cache[fc] = result

proc chunk_bytes*(self: VoxelStore, fc: FrameChunk): SnapshotData =
  ## One chunk of any frame, packed. A snapshot-only chunk hands back its
  ## stored blob verbatim; one with deltas or pending writes is composed and
  ## re-encoded. Empty when the chunk holds nothing.
  if not ?self.build:
    return
  let has_deltas = fc in self.chunk_deltas and self.chunk_deltas[fc].len > 0
  if not has_deltas and fc notin self.pending_chunks:
    if fc in self.packed_chunks:
      return self.packed_chunks[fc]
    return
  let chunk = self.compose_chunk(fc)
  if chunk.count > 0:
    result = encode_chunk(chunk.cells)

proc prefill_bytes*(self: VoxelStore, chunk_id: Vector3): string =
  ## The packed bytes a paged-in engine block is prefilled with so it renders
  ## complete on its first (and only) mesh: the targeted frame's chunk,
  ## composed with any deltas so the block arrives whole instead of
  ## snapshot-then-delta-repaint. "" when the chunk holds nothing or hasn't
  ## synced here yet (the block loads empty and repaints when it lands).
  self.chunk_bytes(self.key(chunk_id)).data

iterator frame_chunk_ids*(self: VoxelStore, frame_id: int): Vector3 =
  ## Every chunk of a frame that may hold voxels, deduped across the synced
  ## tables, the write buffer, and the cache (which is authoritative on a
  ## standalone store).
  var seen: HashSet[Vector3]
  if ?self.build:
    for fc in self.packed_chunks.value.keys:
      if fc.frame == frame_id and not seen.contains_or_incl(fc.loc):
        yield fc.loc
    for fc in self.chunk_deltas.value.keys:
      if fc.frame == frame_id and not seen.contains_or_incl(fc.loc):
        yield fc.loc
  for fc in self.pending_chunks.keys:
    if fc.frame == frame_id and not seen.contains_or_incl(fc.loc):
      yield fc.loc
  for fc in self.chunk_cache.keys:
    if fc.frame == frame_id and not seen.contains_or_incl(fc.loc):
      yield fc.loc

iterator chunk_ids*(self: VoxelStore): Vector3 =
  ## The targeted frame's chunks: the id set bulk operations walk.
  for chunk_id in self.frame_chunk_ids(self.frame_id):
    yield chunk_id

proc peek_chunk(self: VoxelStore, fc: FrameChunk): CachedChunk =
  ## The chunk's cells without inserting into the cache: bulk iteration uses
  ## this so a whole-build scan can't flush main's hot interactive set.
  self.chunk_cache.with_value(fc, entry):
    return entry[]
  self.compose_chunk(fc)

proc unpack_info(self: VoxelStore, packed: PackedVoxel): VoxelInfo =
  let (color_idx, kind_ord) = unpack_voxel(packed)
  (VoxelKind(kind_ord), resolve_color(self.shared_of, color_idx))

proc cell(self: VoxelStore, position: Vector3): PackedVoxel =
  self.cached_chunk(self.key(position.buffer)).cells[linear_position(position)]

proc contains*(self: VoxelStore, position: Vector3): bool =
  self.cell(position) != EMPTY_VOXEL

proc voxel_info*(self: VoxelStore, position: Vector3): VoxelInfo =
  self.unpack_info(self.cell(position))

proc find_voxel*(self: VoxelStore, position: Vector3): Option[VoxelInfo] =
  let packed = self.cell(position)
  if packed != EMPTY_VOXEL:
    some(self.unpack_info(packed))
  else:
    none(VoxelInfo)

proc should_use_snapshot(
    has_existing: bool, change_count, delta_count: int, is_empty: bool
): bool =
  not has_existing or change_count > MAX_CHANGES_FOR_DELTA or
    delta_count >= MAX_DELTAS_BEFORE_SNAPSHOT or is_empty

proc edit_cells(self: VoxelStore, fc: FrameChunk): array[CHUNK_VOLUME, PackedVoxel] =
  ## A chunk's edits as stored in the synced tables: snapshot ⊕ deltas.
  if not ?self.edit_snapshots:
    return
  let key = self.edit_key(fc)
  if key in self.edit_snapshots:
    result = decode_chunk(self.edit_snapshots[key])
  if ?self.edit_deltas and key in self.edit_deltas:
    let deltas = self.edit_deltas[key]
    if ?deltas:
      for delta in deltas:
        for (local_pos, packed_voxel) in decode_delta(delta):
          result[linear_position(local_pos)] = packed_voxel

proc load_edits(self: VoxelStore, fc: FrameChunk) =
  ## Decode a chunk's edits on first use: the synced rows, then this side's
  ## unflushed writes. Main decodes again in each new frame, since the worker
  ## and other players change the rows underneath it.
  if self.ctx.metrics_label == "main" and self.edits_frame != state.frame_count:
    self.edits_frame = state.frame_count
    self.local_edits.clear()
    self.edits_loaded.clear()
  if self.edits_loaded.contains_or_incl(fc):
    return
  var cells = self.edit_cells(fc)
  if fc in self.pending_edits:
    for (local_pos, packed) in self.pending_edits[fc]:
      cells[linear_position(local_pos)] = packed
  for linear in 0 ..< CHUNK_VOLUME:
    if cells[linear] != EMPTY_VOXEL:
      let (color_idx, kind_ord) = unpack_voxel(cells[linear])
      self.local_edits.mget_or_put(fc, Table[Vector3, VoxelInfo].init)[
        from_linear(linear)
      ] = (VoxelKind(kind_ord), resolve_color(self.shared_of, color_idx))

proc forget_edits(self: VoxelStore, fc: FrameChunk) =
  self.edits_loaded.excl fc
  self.local_edits.del fc
  self.hole_chunks.del fc
  self.hole_free_frames.excl fc.frame

proc edit_row_changed*(self: VoxelStore, fc: FrameChunk) =
  ## A chunk's edit row changed. Unless this side wrote it, the decoded copy
  ## is stale.
  if not self.writing_edits:
    self.forget_edits(fc)

template writing(self: VoxelStore, body: untyped) =
  let previous = self.writing_edits
  self.writing_edits = true
  try:
    body
  finally:
    self.writing_edits = previous

proc edit_chunk_ids*(self: VoxelStore, frame_id: int): seq[Vector3] =
  ## Every chunk of a frame that may hold edits.
  var seen: HashSet[Vector3]
  if ?self.edit_snapshots:
    for key in self.edit_snapshots.value.keys:
      if key.id == self.thing_id and key.frame == frame_id and
          not seen.contains_or_incl(key.loc):
        result.add key.loc
    for key in self.edit_deltas.value.keys:
      if key.id == self.thing_id and key.frame == frame_id and
          not seen.contains_or_incl(key.loc):
        result.add key.loc
  for fc in self.local_edits.keys:
    if fc.frame == frame_id and not seen.contains_or_incl(fc.loc):
      result.add fc.loc

proc has_holes(self: VoxelStore, fc: FrameChunk): bool =
  ## Whether a chunk's edits hold a hole, remembered until its row changes.
  ## A chunk not yet decoded is checked in its packed row.
  self.hole_chunks.with_value(fc, known):
    return known[]
  if fc in self.edits_loaded or fc in self.pending_edits:
    self.load_edits(fc)
    if fc in self.local_edits:
      for info in self.local_edits[fc].values:
        if info.kind == HOLE:
          result = true
          break
  else:
    for v in self.edit_cells(fc):
      if v != EMPTY_VOXEL and VoxelKind(unpack_voxel(v)[1]) == HOLE:
        result = true
        break
  self.hole_chunks[fc] = result

proc build_edit_state(
    self: VoxelStore, fc: FrameChunk
): array[CHUNK_VOLUME, PackedVoxel] =
  self.load_edits(fc)
  if fc in self.local_edits:
    for local_pos, info in self.local_edits[fc]:
      let linear = linear_position(local_pos)
      if linear >= 0 and linear < CHUNK_VOLUME:
        result[linear] =
          pack_voxel(pack_color_index(self.shared_of, info.color), info.kind.ord)

proc flush_chunk_snapshot(self: VoxelStore, fc: FrameChunk) =
  let packed = encode_chunk(self.cached_chunk(fc).cells)

  if packed.is_empty:
    if fc in self.packed_chunks:
      self.packed_chunks.del(fc)
    if fc in self.chunk_deltas:
      self.chunk_deltas.del(fc)
  else:
    self.packed_chunks[fc] = packed
    if fc in self.chunk_deltas:
      self.chunk_deltas[fc].clear

  inc self.snapshots_flushed

proc flush_chunk_delta(
    self: VoxelStore,
    fc: FrameChunk,
    changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]],
) =
  let delta = encode_delta(changes)

  if fc notin self.chunk_deltas:
    # Own the nested seq under its table's owner (the build): it's created here
    # during drawing — outside any own scope — and an unowned container escapes
    # the destroy cascade, leaking on every reload.
    let table_owner = self.chunk_deltas.owner_id
    table_owner.own:
      self.chunk_deltas[fc] =
        EdSeq[DeltaUpdate].init(flags = {SYNC_LOCAL, SYNC_REMOTE})

  self.chunk_deltas[fc].add delta
  inc self.deltas_flushed

iterator flush_dirty_chunks*(self: VoxelStore): FrameChunk =
  ## Flush each dirty chunk as one synced message, yielding its key after it's
  ## flushed and removed from `pending_chunks`. The caller drives the cadence and
  ## may stop early -- the worker breaks on channel pressure -- leaving the
  ## remaining chunks to coalesce and flush on a later frame, so a single large
  ## (ASAP) draw burst can't overshoot the channel in one go. Drain it fully (the
  ## `proc` overload below) to flush everything, e.g. for save / end_asap.
  # Bulk-adopted snapshots first. A staged blob is the chunk's state as of
  # adoption, so it belongs underneath anything drawn since — draining it
  # after the pending draws republished a stale blob over fresher content and
  # cleared their deltas, losing the drawing outright.
  for fc in self.pending_snapshots.keys.to_seq:
    let blob = self.pending_snapshots[fc]
    # A snapshot supersedes a chunk's deltas and pending changes only when it
    # was encoded from that chunk's current cells. The staged blob wasn't, so
    # it's authoritative only while the chunk is untouched since adoption.
    # Once something has drawn into it, re-encode from the cells — those
    # already fold packed (+) deltas (+) pending — and let that supersede.
    # (Ordering alone wouldn't do: the worker breaks out of this iterator on
    # channel pressure, so a staged blob can outlive a pass in which draws
    # flushed.)
    if blob.data.len == 0 or fc in self.pending_chunks:
      self.flush_chunk_snapshot(fc)
      self.pending_chunks.del fc
    else:
      self.packed_chunks[fc] = blob # bulk-adopted, publish verbatim
      if fc in self.chunk_deltas:
        self.chunk_deltas[fc].clear
      inc self.snapshots_flushed
    self.pending_snapshots.del fc
    yield fc
  for fc in self.pending_chunks.keys.to_seq:
    let changes = self.pending_chunks[fc]
    let has_snapshot = fc in self.packed_chunks
    let delta_count =
      if fc in self.chunk_deltas:
        self.chunk_deltas[fc].len
      else:
        0
    let chunk_empty = self.cached_chunk(fc).count == 0

    if should_use_snapshot(has_snapshot, changes.len, delta_count, chunk_empty):
      self.flush_chunk_snapshot(fc)
    else:
      self.flush_chunk_delta(fc, changes)
    self.pending_chunks.del fc
    yield fc

proc flush_dirty_chunks*(self: VoxelStore) =
  ## Flush every dirty chunk (save / end_asap). The worker uses the iterator form
  ## to flush incrementally and stop under channel pressure.
  for _ in self.flush_dirty_chunks():
    discard

proc flush_edit_snapshot(self: VoxelStore, fc: FrameChunk) =
  let key = self.edit_key(fc)
  let packed = encode_chunk(self.build_edit_state(fc))

  self.writing:
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
    fc: FrameChunk,
    changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]],
) =
  let key = self.edit_key(fc)
  let delta = encode_delta(changes)

  self.writing:
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

  for fc, changes in self.pending_edits:
    self.load_edits(fc)
    let key = self.edit_key(fc)
    let has_snapshot = key in self.edit_snapshots
    let delta_count =
      if key in self.edit_deltas:
        self.edit_deltas[key].len
      else:
        0
    let chunk_empty = fc notin self.local_edits or self.local_edits[fc].len == 0

    if should_use_snapshot(has_snapshot, changes.len, delta_count, chunk_empty):
      self.flush_edit_snapshot(fc)
    else:
      self.flush_edit_delta(fc, changes)

  self.pending_edits.clear

proc rebuild_local_edits*(self: VoxelStore)
proc set_edit*(self: VoxelStore, position: Vector3, info: VoxelInfo)
proc flush_edits_for_save*(self: VoxelStore) =
  ## Fold every edit chunk's deltas into its snapshot, so the save reads
  ## snapshots alone.
  self.flush_dirty_edits()
  {.cast(gcsafe).}:
    self.rebuild_local_edits()
  if not ?self.edit_deltas:
    return
  var chunked: seq[FrameChunk]
  for key, deltas in self.edit_deltas.value:
    if key.id == self.thing_id and ?deltas and deltas.len > 0:
      chunked.add (key.frame, key.loc)
  for fc in chunked:
    self.flush_edit_snapshot(fc)

proc adopt_chunk(
    self: VoxelStore, fc: FrameChunk,
    cells: array[CHUNK_VOLUME, PackedVoxel], snapshot: SnapshotData,
    changed: bool,
): bool =
  ## Install one bulk-restored chunk: cells into the read cache, and the
  ## packed form into the synced table (the stored blob verbatim when the
  ## cells match it exactly). Returns whether the chunk's edits hold a hole.
  let chunk = CachedChunk()
  var dropped = changed
  for linear in 0 ..< CHUNK_VOLUME:
    let v = cells[linear]
    if v == EMPTY_VOXEL:
      continue
    let (_, kind_ord) = unpack_voxel(v)
    if VoxelKind(kind_ord) == HOLE:
      dropped = true # erases nothing with no base; excluded from live state
      result = true
      continue
    chunk.cells[linear] = v
    inc chunk.count
  # Bounds first, and for every adopted chunk: an all-HOLE chunk installs
  # nothing but still occupies space the terrain has to be allowed to load,
  # and `chunk_ids` counts it, so reset_bounds would cover it anyway.
  self.note_chunk(fc.loc)
  if chunk.count == 0:
    return
  inc self.cache_tick
  chunk.tick = self.cache_tick
  self.chunk_cache[fc] = chunk
  # Stage for the paced flusher rather than publishing here: load adopts
  # thousands of chunks, and pushing them all through sync in one burst
  # overwhelms the channel right when boot is busiest.
  self.pending_snapshots[fc] =
    if dropped:
      SnapshotData()
    else:
      snapshot

proc has_live_content(self: VoxelStore): bool =
  for fc in self.chunk_cache.keys:
    if fc.frame == self.frame_id:
      return true
  for fc in self.pending_chunks.keys:
    if fc.frame == self.frame_id:
      return true
  for fc in self.pending_snapshots.keys:
    if fc.frame == self.frame_id:
      return true

proc adopt_edit_chunks*(self: VoxelStore): bool =
  ## Bulk restore of the targeted frame when it has no live content — the
  ## fresh-load path of a persisted build, where the edits ARE the content.
  ## Each edit chunk's packed cells are adopted directly as the live chunk and
  ## published as one snapshot, instead of round-tripping every voxel through
  ## unpack/resolve_color -> add_voxel/pack_color_index (seconds per million
  ## voxels at load, plus a redundant set_edit per voxel). HOLE edits erase
  ## from a base; with no base they are no-ops and are skipped. Returns false
  ## when live content already exists (script rerun/reset) — the caller keeps
  ## the per-voxel overlay semantics. Every edit chunk passes through here,
  ## so it also learns whether the frame holds any holes.
  if self.has_live_content:
    return false
  var handled = init_hash_set[Vector3]()
  var holes = false
  if ?self.edit_snapshots:
    for key, snapshot in self.edit_snapshots:
      if key.id != self.thing_id or key.frame != self.frame_id:
        continue
      var cells = decode_chunk(snapshot)
      var changed = false
      if ?self.edit_deltas and key in self.edit_deltas:
        let delta_seq = self.edit_deltas[key]
        if ?delta_seq:
          for delta in delta_seq:
            for (local_pos, packed_voxel) in decode_delta(delta):
              cells[
                linear_position(local_pos.x.int, local_pos.y.int, local_pos.z.int)
              ] = packed_voxel
              changed = true
      handled.incl key.loc
      let fc = self.key(key.loc)
      self.hole_chunks[fc] = self.adopt_chunk(fc, cells, snapshot, changed)
      holes = holes or self.hole_chunks[fc]
  if ?self.edit_deltas:
    for key, delta_seq in self.edit_deltas:
      if key.id != self.thing_id or key.frame != self.frame_id or
          key.loc in handled or not ?delta_seq:
        continue
      var cells: array[CHUNK_VOLUME, PackedVoxel]
      for delta in delta_seq:
        for (local_pos, packed_voxel) in decode_delta(delta):
          cells[
            linear_position(local_pos.x.int, local_pos.y.int, local_pos.z.int)
          ] = packed_voxel
      let fc = self.key(key.loc)
      self.hole_chunks[fc] =
        self.adopt_chunk(fc, cells, SnapshotData(), changed = true)
      holes = holes or self.hole_chunks[fc]
  if not holes:
    self.hole_free_frames.incl self.frame_id
  self.restored_frames.incl self.frame_id
  true

proc restore_needed*(self: VoxelStore): bool =
  ## Whether reset() must rebuild the targeted frame (clear + restore_edits).
  ## Kind is the ground truth — persisted edits restore as PERSISTED cells,
  ## scripts draw TRANSIENT ones — so:
  ## - any TRANSIENT cell → a script drew since the last restore: rebuild
  ##   (early exit on the first one found; a unit that completed a reset
  ##   before carries at least the TRANSIENT default origin block).
  ## - no cells at all → nothing restored yet (or a genuinely empty unit,
  ##   where the rebuild is a cheap no-op): rebuild.
  ## - non-empty and all PERSISTED → the live state is already exactly the
  ##   restored edits: skip. Without this, a load's phase 2 cleared and
  ##   remeshed identical content in front of the player (the sea rebuilt
  ##   itself right after the reveal).
  ## Accepted blind spot: a script whose only effect was erasing persisted
  ## voxels (drawing nothing, not even keeping the default origin block)
  ## reads as pristine, so removing that script's erase code and reloading
  ## won't resurrect the erased voxels — rerunning the script reproduces
  ## the same state anyway.
  ## The answer is remembered per frame until a computed block lands in it
  ## or its blocks are replaced.
  if self.frame_id in self.restored_frames:
    return false
  var has_content = false
  for chunk_id in self.chunk_ids.to_seq:
    let chunk = self.cached_chunk(self.key(chunk_id))
    if chunk.count == 0:
      continue
    has_content = true
    for linear in 0 ..< CHUNK_VOLUME:
      let v = chunk.cells[linear]
      if v == EMPTY_VOXEL:
        continue
      let (_, kind_ord) = unpack_voxel(v)
      if VoxelKind(kind_ord) == TRANSIENT:
        return true
  if has_content:
    self.restored_frames.incl self.frame_id
  not has_content

proc local_pos_of(position: Vector3): Vector3 =
  vec3(
    floor_mod(position.x.int, 16).float,
    floor_mod(position.y.int, 16).float,
    floor_mod(position.z.int, 16).float,
  )

proc add_voxel*(self: VoxelStore, position: Vector3, voxel: VoxelInfo) =
  let fc = self.key(position.buffer)
  let chunk = self.cached_chunk(fc)
  let linear = linear_position(position)

  self.note_chunk(fc.loc)
  if voxel.kind == TRANSIENT:
    self.restored_frames.excl fc.frame

  let packed =
    pack_voxel(pack_color_index(self.shared_of, voxel.color), voxel.kind.ord)
  if chunk.cells[linear] == EMPTY_VOXEL:
    inc chunk.count
  chunk.cells[linear] = packed

  let local_pos = local_pos_of(position)

  if self.ctx.metrics_label == "main" or self.immediate:
    self.flush_chunk_delta(fc, @[(local_pos, packed)])
    let delta_count =
      if fc in self.chunk_deltas:
        self.chunk_deltas[fc].len
      else:
        0
    if should_use_snapshot(fc in self.packed_chunks, 1, delta_count, false):
      self.flush_chunk_snapshot(fc)
  else:
    self.pending_chunks.mgetOrPut(fc, @[]).add (local_pos, packed)

  if voxel.kind == PERSISTED:
    {.cast(gcsafe).}:
      self.set_edit(position, voxel)

proc del_voxel*(self: VoxelStore, position: Vector3) =
  let fc = self.key(position.buffer)
  let chunk = self.cached_chunk(fc)
  let linear = linear_position(position)
  if chunk.cells[linear] != EMPTY_VOXEL:
    chunk.cells[linear] = EMPTY_VOXEL
    dec chunk.count

    let local_pos = local_pos_of(position)
    let packed = EMPTY_VOXEL

    if self.ctx.metrics_label == "main" or self.immediate:
      self.flush_chunk_delta(fc, @[(local_pos, packed)])
      let delta_count =
        if fc in self.chunk_deltas:
          self.chunk_deltas[fc].len
        else:
          0
      let chunk_empty = chunk.count == 0
      if should_use_snapshot(
        fc in self.packed_chunks, 1, delta_count, chunk_empty
      ):
        self.flush_chunk_snapshot(fc)
    else:
      self.pending_chunks.mgetOrPut(fc, @[]).add (local_pos, packed)

proc has_edit*(self: VoxelStore, position: Vector3): bool =
  let fc = self.key(chunk_id_for_pos(position))
  self.load_edits(fc)
  fc in self.local_edits and local_pos_in_chunk(position) in self.local_edits[fc]

proc get_edit*(self: VoxelStore, position: Vector3): VoxelInfo =
  let fc = self.key(chunk_id_for_pos(position))
  self.load_edits(fc)
  self.local_edits[fc][local_pos_in_chunk(position)]

proc set_edit*(self: VoxelStore, position: Vector3, info: VoxelInfo) =
  let fc = self.key(chunk_id_for_pos(position))
  let local_pos = local_pos_in_chunk(position)
  self.load_edits(fc)

  if fc notin self.local_edits:
    self.local_edits[fc] = Table[Vector3, VoxelInfo].init
  self.local_edits[fc][local_pos] = info
  if info.kind == HOLE:
    self.hole_chunks[fc] = true
    self.hole_free_frames.excl fc.frame
  elif self.hole_chunks.get_or_default(fc):
    self.hole_chunks.del fc

  let packed =
    pack_voxel(pack_color_index(self.shared_of, info.color), info.kind.ord)

  if self.ctx.metrics_label == "main" or self.immediate:
    self.flush_edit_delta(fc, @[(local_pos, packed)])
    let key = self.edit_key(fc)
    let delta_count =
      if key in self.edit_deltas:
        self.edit_deltas[key].len
      else:
        0
    if should_use_snapshot(key in self.edit_snapshots, 1, delta_count, false):
      self.flush_edit_snapshot(fc)
  else:
    self.pending_edits.mgetOrPut(fc, @[]).add (local_pos, packed)

proc del_edit*(self: VoxelStore, position: Vector3) =
  let fc = self.key(chunk_id_for_pos(position))
  let local_pos = local_pos_in_chunk(position)
  self.load_edits(fc)

  if fc in self.local_edits and local_pos in self.local_edits[fc]:
    self.local_edits[fc].del(local_pos)
    if self.local_edits[fc].len == 0:
      self.local_edits.del(fc)
    if self.hole_chunks.get_or_default(fc):
      self.hole_chunks.del fc

    let packed = EMPTY_VOXEL
    if self.ctx.metrics_label == "main" or self.immediate:
      self.flush_edit_delta(fc, @[(local_pos, packed)])
      let key = self.edit_key(fc)
      let delta_count =
        if key in self.edit_deltas:
          self.edit_deltas[key].len
        else:
          0
      let chunk_empty = fc notin self.local_edits or self.local_edits[fc].len == 0
      if should_use_snapshot(
        key in self.edit_snapshots, 1, delta_count, chunk_empty
      ):
        self.flush_edit_snapshot(fc)
    else:
      self.pending_edits.mgetOrPut(fc, @[]).add (local_pos, packed)

template for_edits_in(self: VoxelStore, chunk_ids: seq[Vector3], body: untyped) =
  for chunk_id in chunk_ids:
    let fc: FrameChunk = (self.frame_id, chunk_id)
    self.load_edits(fc)
    if fc in self.local_edits:
      for local_pos, info {.inject.} in self.local_edits[fc]:
        let pos {.inject.} = vec3(
          chunk_id.x * ChunkDim + local_pos.x,
          chunk_id.y * ChunkDim + local_pos.y,
          chunk_id.z * ChunkDim + local_pos.z,
        )
        body

template for_all_edits*(self: VoxelStore, body: untyped) =
  ## Every edit of the targeted frame.
  self.for_edits_in(self.edit_chunk_ids(self.frame_id), body)

template for_hole_edits*(self: VoxelStore, body: untyped) =
  ## Every edit of the targeted frame's chunks that hold holes. Each chunk is
  ## checked once (`has_holes`), and a frame found to have none is skipped
  ## until a row of it changes, so a frame of hand-placed blocks isn't
  ## decoded on every run to find none.
  if self.frame_id notin self.hole_free_frames:
    var with_holes: seq[Vector3]
    for chunk_id in self.edit_chunk_ids(self.frame_id):
      if self.has_holes((self.frame_id, chunk_id)):
        with_holes.add chunk_id
    if with_holes.len == 0:
      self.hole_free_frames.incl self.frame_id
    self.for_edits_in(with_holes, body)

proc rebuild_local_edits*(self: VoxelStore) =
  ## Forget the decoded edits; each chunk decodes again from the synced edit
  ## tables on its next use.
  self.local_edits.clear()
  self.edits_loaded.clear()

proc apply_snapshot*(
    self: VoxelStore, fc: FrameChunk, snapshot: SnapshotData
) =
  ## A whole-chunk snapshot arrived (sync watch): the cached decode, if any,
  ## is stale -- drop it and let the next read compose from the new blob.
  ## Nothing decodes until something actually reads the chunk. On a
  ## standalone store (no Build) there is no synced table to re-read, so the
  ## decode installs directly: the cache is the store.
  if snapshot.data.len == 0:
    return
  self.note_chunk(fc.loc)
  self.restored_frames.excl fc.frame
  if ?self.build:
    self.chunk_cache.del(fc)
  else:
    let chunk = CachedChunk(cells: decode_chunk(snapshot))
    for v in chunk.cells:
      if v != EMPTY_VOXEL:
        inc chunk.count
    self.chunk_cache[fc] = chunk

proc unload_chunk*(self: VoxelStore, fc: FrameChunk) =
  ## Drop a paged-out chunk's local state (the voxel paging counterpart of
  ## apply_snapshot). The data still exists on the authority; a later
  ## `request` re-applies it.
  ##
  ## "The authority has it" holds for flushed content only. Unflushed writes
  ## in `pending_chunks` have not reached the synced tables, so dropping them
  ## here loses them outright — the same hazard `cached_chunk`'s eviction
  ## invariant refuses to take.
  if fc in self.pending_chunks:
    warn "page-out dropping unflushed voxel writes",
      unit = self.thing_id,
      chunk = $fc.loc,
      writes = self.pending_chunks[fc].len
  self.restored_frames.excl fc.frame
  self.chunk_cache.del(fc)
  self.pending_chunks.del(fc)

proc apply_delta*(self: VoxelStore, fc: FrameChunk, delta: DeltaUpdate) =
  ## A delta arrived (sync watch): poke a cached decode in place; an uncached
  ## chunk needs nothing -- the next read composes the delta from the table.
  self.restored_frames.excl fc.frame
  self.chunk_cache.with_value(fc, entry):
    for (local_pos, packed_voxel) in decode_delta(delta):
      let linear = linear_position(local_pos)
      if entry[].cells[linear] != EMPTY_VOXEL:
        dec entry[].count
      if packed_voxel != EMPTY_VOXEL:
        inc entry[].count
      entry[].cells[linear] = packed_voxel

# Whole frames. These take frame ids, not indexes.

proc frame_data*(self: VoxelStore, frame_id: int): FrameData =
  ## Every chunk of a frame, packed: computed and manual blocks.
  for chunk_id in self.frame_chunk_ids(frame_id).to_seq:
    let packed = self.chunk_bytes((frame_id, chunk_id))
    if not packed.is_empty:
      result.chunks[chunk_id] = packed

proc frame_edits*(self: VoxelStore, frame_id: int): FrameData =
  ## A frame's manual blocks and holes, packed: what gets saved.
  for chunk_id in self.edit_chunk_ids(frame_id):
    let fc: FrameChunk = (frame_id, chunk_id)
    let key = self.edit_key(fc)
    let packed =
      if fc in self.edits_loaded:
        encode_chunk(self.build_edit_state(fc))
      elif key in self.edit_snapshots and
          (key notin self.edit_deltas or self.edit_deltas[key].len == 0):
        self.edit_snapshots[key]
      else:
        encode_chunk(self.edit_cells(fc))
    if not packed.is_empty:
      result.chunks[chunk_id] = packed

proc drop_frame*(self: VoxelStore, frame_id: int) =
  ## Remove every row of a frame: its blocks and its edits.
  if ?self.build:
    for fc in self.packed_chunks.value.keys:
      if fc.frame == frame_id:
        self.packed_chunks.del(fc)
    for fc in self.chunk_deltas.value.keys:
      if fc.frame == frame_id:
        self.chunk_deltas.del(fc)
  if ?self.edit_snapshots:
    for key in self.edit_snapshots.value.keys:
      if key.id == self.thing_id and key.frame == frame_id:
        self.edit_snapshots.del(key)
    for key in self.edit_deltas.value.keys:
      if key.id == self.thing_id and key.frame == frame_id:
        self.edit_deltas.del(key)
  for table in [addr self.pending_chunks, addr self.pending_edits]:
    for fc in table[].keys.to_seq:
      if fc.frame == frame_id:
        table[].del fc
  for fc in self.pending_snapshots.keys.to_seq:
    if fc.frame == frame_id:
      self.pending_snapshots.del fc
  for fc in self.chunk_cache.keys.to_seq:
    if fc.frame == frame_id:
      self.chunk_cache.del fc
  for fc in self.local_edits.keys.to_seq:
    if fc.frame == frame_id:
      self.local_edits.del fc
  for fc in self.edits_loaded.to_seq:
    if fc.frame == frame_id:
      self.edits_loaded.excl fc
  for fc in self.hole_chunks.keys.to_seq:
    if fc.frame == frame_id:
      self.hole_chunks.del fc
  self.hole_free_frames.excl frame_id
  self.restored_frames.excl frame_id

proc install_frame*(
    self: VoxelStore, frame_id: int, blocks, edits: FrameData
) =
  ## Fill an empty frame a chunk at a time: `blocks` as its chunks, `edits`
  ## as its manual blocks and holes.
  self.restored_frames.excl frame_id
  for chunk_id, packed in blocks.chunks:
    let fc: FrameChunk = (frame_id, chunk_id)
    self.apply_snapshot(fc, packed)
    if ?self.build:
      self.packed_chunks[fc] = packed
  if ?self.edit_snapshots:
    for chunk_id, packed in edits.chunks:
      let fc: FrameChunk = (frame_id, chunk_id)
      self.edit_snapshots[self.edit_key(fc)] = packed
      self.forget_edits(fc)

proc load_frame_edits*(
    self: VoxelStore, frame_id: int, edits: FrameData, adopt = true
) =
  ## Restore a saved frame — its manual blocks and holes — into an empty
  ## frame, a chunk at a time. `adopt = false` restores only the edits,
  ## leaving the blocks to a later `adopt_edit_chunks`.
  if ?self.edit_snapshots:
    for chunk_id, packed in edits.chunks:
      let fc: FrameChunk = (frame_id, chunk_id)
      self.edit_snapshots[self.edit_key(fc)] = packed
      self.forget_edits(fc)
  if adopt:
    self.with_frame(frame_id):
      discard self.adopt_edit_chunks()

proc copy_frame*(self: VoxelStore, src, dst: int) =
  ## Frame `dst` becomes a copy of frame `src`.
  self.flush_dirty_chunks()
  self.flush_dirty_edits()
  self.drop_frame(dst)
  self.install_frame(dst, self.frame_data(src), self.frame_edits(src))

proc overlay(base: var FrameData, top: FrameData) =
  for chunk_id, packed in top.chunks:
    var cells =
      if chunk_id in base.chunks: decode_chunk(base.chunks[chunk_id])
      else: default(array[CHUNK_VOLUME, PackedVoxel])
    let top_cells = decode_chunk(packed)
    for i in 0 ..< CHUNK_VOLUME:
      if top_cells[i] != EMPTY_VOXEL:
        cells[i] = top_cells[i]
    base.chunks[chunk_id] = encode_chunk(cells)

proc paste_frame*(self: VoxelStore, src, dst: int) =
  ## Lay frame `src`'s blocks and edits over frame `dst`'s; `src` wins where
  ## both have one.
  self.flush_dirty_chunks()
  self.flush_dirty_edits()
  var blocks = self.frame_data(dst)
  var edits = self.frame_edits(dst)
  blocks.overlay(self.frame_data(src))
  edits.overlay(self.frame_edits(src))
  self.drop_frame(dst)
  self.install_frame(dst, blocks, edits)

proc swap_color*(self: VoxelStore, from_color, to_color: Color) =
  ## Recolour every voxel of `from_color` to `to_color` in the targeted frame,
  ## across both the computed chunk state and the persisted (manual) edits.
  ## Pending writes are flushed first so they can't re-apply the old colour
  ## after the swap. Used to build invisible walls: draw in a spare colour,
  ## then swap it to `invisible`.
  let shared = self.shared_of
  let from_idx = pack_color_index(shared, from_color)
  let to_idx = pack_color_index(shared, to_color)
  if from_idx == to_idx:
    return

  self.flush_dirty_chunks()
  for chunk_id in self.chunk_ids.to_seq:
    let fc = self.key(chunk_id)
    let chunk = self.cached_chunk(fc)
    var changed = false
    for linear in 0 ..< CHUNK_VOLUME:
      let packed = chunk.cells[linear]
      if packed != EMPTY_VOXEL:
        let (color_idx, kind_ord) = unpack_voxel(packed)
        if color_idx == from_idx:
          chunk.cells[linear] = pack_voxel(to_idx, kind_ord)
          changed = true
    if changed:
      self.flush_chunk_snapshot(fc)

  self.flush_dirty_edits()
  for chunk_id in self.edit_chunk_ids(self.frame_id):
    let fc = self.key(chunk_id)
    self.load_edits(fc)
    if fc notin self.local_edits:
      continue
    var changed = false
    for local_pos, info in self.local_edits[fc].mpairs:
      if info.color == from_color:
        info.color = to_color
        changed = true
    if changed:
      self.flush_edit_snapshot(fc)

proc clear*(self: VoxelStore, all = false) =
  ## Empty the targeted frame's blocks. `clear` normally spares the persisted
  ## edits (a reset clears the render state and restores from them); pass
  ## all = true when the edits must go too.
  self.restored_frames.excl self.frame_id
  for chunk_id in self.chunk_ids.to_seq:
    let fc = self.key(chunk_id)
    self.chunk_cache.del fc
    self.pending_chunks.del fc
    self.pending_snapshots.del fc
    if ?self.build:
      if fc in self.packed_chunks:
        self.packed_chunks.del(fc)
      if fc in self.chunk_deltas:
        self.chunk_deltas.del(fc)
  if all:
    if ?self.edit_snapshots:
      for key in self.edit_snapshots.value.keys:
        if key.id == self.thing_id and key.frame == self.frame_id:
          self.edit_snapshots.del(key)
      for key in self.edit_deltas.value.keys:
        if key.id == self.thing_id and key.frame == self.frame_id:
          self.edit_deltas.del(key)
    for fc in self.local_edits.keys.to_seq:
      if fc.frame == self.frame_id:
        self.local_edits.del fc
    for fc in self.edits_loaded.to_seq:
      if fc.frame == self.frame_id:
        self.edits_loaded.excl fc
    for fc in self.hole_chunks.keys.to_seq:
      if fc.frame == self.frame_id:
        self.hole_chunks.del fc
    self.hole_free_frames.excl self.frame_id
    for fc in self.pending_edits.keys.to_seq:
      if fc.frame == self.frame_id:
        self.pending_edits.del fc

iterator all_voxels*(self: VoxelStore): tuple[pos: Vector3, info: VoxelInfo] =
  ## Every voxel of the targeted frame with its world position, streaming
  ## chunk by chunk. Reads through `peek_chunk` (no cache insertion) so a
  ## whole-build scan can't flush main's interactive working set.
  for chunk_id in self.chunk_ids.to_seq:
    let chunk = self.peek_chunk(self.key(chunk_id))
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
