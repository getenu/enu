## Frame-animation playback for BuildNode, extracted so the node itself stays
## about node lifecycle. A FramePlayer owns all the frame state (the mesh
## cache, the per-chunk display/queue/miss bookkeeping, the decode scratch) and
## drives a build's flipbook: `show` queues a frame, `drain` applies it under a
## time budget, `commit_meshes` swaps the prepared meshes atomically, and
## `on_mesh_baked` folds asynchronous bakes back in.
##
## It reaches the terrain through the VoxelTerrain base (set_block_mesh,
## request_frame_mesh, set_block_voxel_data, get_debug_paired_viewers are all
## base-class bindings), so it never depends on BuildNode — no import cycle.
## `loaded_chunks` is the node's own set, held by pointer (same lifetime).

import std/[tables, times, monotimes, options, sets, hashes, algorithm]
from std/os import get_env
import pkg/godot except print, Color
import godotapi/[voxel_terrain, mesh]
import core, models/voxels
import ./voxel_library_registry

const
  # Temporal LOD for frame playback, in world metres from the nearest viewer:
  # full frame rate inside NEAR, every MID_STEPth frame out to MID, a static
  # frame beyond. Distant waves are a few pixels tall, so quantizing them is
  # visually free — and it bounds the mesh cache by the near disc instead of
  # the whole loaded area (the 250m+ seas).
  frame_lod_near = 96.0
  frame_lod_mid = 160.0
  frame_lod_mid_step = 4

# Read once at load. ENU_FRAME_LOD=0 disables LOD so every chunk animates at
# full rate regardless of distance — for A/B testing the LOD savings.
let frame_lod_enabled* = get_env("ENU_FRAME_LOD", "1") != "0"

type FramePlayer* = ref object
  # Collaborators (set at init, live as long as the node does).
  terrain {.cursor.}: VoxelTerrain
  model {.cursor.}: Build
  renderer: VoxelRenderer
  resolver: ColorIndexResolver
  loaded_chunks: ptr HashSet[Vector3]
    ## the node's own loaded-chunk set, by pointer (never owned here)

  # Applying a frame writes the chunk's voxel data the way any edit would. A
  # chunk whose content key has a cached mesh gets it set directly (the write
  # suppresses remeshing); a miss meshes through the engine's normal pipeline.
  mesh_cache: Table[Hash, Mesh]
  display: Table[Vector3, Hash] ## content key shown per chunk
  missing: Table[Vector3, tuple[key: Hash, at: MonoTime]]
    ## in-flight bakes: chunk -> the content key the bake was requested for, and
    ## when. Bakes are pure functions of the padded bytes we submit, so the
    ## returned mesh IS the key's content — no attribution gating. A chunk in
    ## here keeps its previous mesh (never a hole) and is skipped by the drain
    ## until its bake lands or times out; everything else keeps animating.
  queue: Table[Vector3, int] ## chunk -> frame index to apply
  staged: Table[Vector3, Mesh]
    ## prepared mesh swaps, held until the whole flip is ready. Data writes and
    ## key work drain incrementally, but the visible change is one atomic pass —
    ## chunks never flip at different times.
  padded_bytes: PoolByteArray ## request_frame_mesh payload scratch
  commit_index: int
    ## which flip `staged` was prepared for. Prepare-ahead builds the NEXT flip
    ## during the current interval; the commit waits until current_frame catches
    ## up, so cadence stays exact.
  decoded: Table[int, DecodedChunks]
    ## lazily decoded chunks per frame index — the working set for per-chunk key
    ## computation inside the drain budget. Pruned each flip to the indexes still
    ## being applied.
  keys: Table[int, Table[Vector3, Hash]] ## per frame, lazily built
  bytes: PoolByteArray ## reusable set_block_voxel_data payload
  dirty: HashSet[Vector3] ## terrain data differs from live state
  mesh_lru: Table[Hash, int] ## last-touched tick per cached mesh
  lru_tick: int
  harvests: int ## since the last stats log
  new_keys: int
  next_stats: MonoTime
  next_at: MonoTime ## next server-side flip deadline
  playback_logged: bool

proc init*(
    _: type FramePlayer,
    terrain: VoxelTerrain,
    model: Build,
    renderer: VoxelRenderer,
    resolver: ColorIndexResolver,
    loaded_chunks: ptr HashSet[Vector3],
): FramePlayer =
  result = FramePlayer(
    terrain: terrain,
    model: model,
    renderer: renderer,
    resolver: resolver,
    loaded_chunks: loaded_chunks,
  )
  result.bytes = new_pool_byte_array()
  result.bytes.set_len(CHUNK_VOLUME * 2)
  result.padded_bytes = new_pool_byte_array()
  result.padded_bytes.set_len((ChunkDim + 2) * (ChunkDim + 2) * (ChunkDim + 2) * 2)

proc touch_cached(self: FramePlayer, key: Hash) =
  inc self.lru_tick
  self.mesh_lru[key] = self.lru_tick

proc store_cached(self: FramePlayer, key: Hash, mesh: Mesh) =
  ## Insert with LRU batch eviction — never a wholesale clear: dropping the
  ## whole cache mid-playback restarts the mesh churn from zero (the misses
  ## re-paste and re-mesh ~everything, every flip, forever).
  const max_cached = 65536
  if self.mesh_cache.len >= max_cached:
    var stamps = new_seq[int](self.mesh_lru.len)
    var i = 0
    for _, stamp in self.mesh_lru:
      stamps[i] = stamp
      inc i
    stamps.sort()
    let cutoff = stamps[stamps.len div 4] # oldest quarter goes
    var evict: seq[Hash]
    for k, stamp in self.mesh_lru:
      if stamp <= cutoff:
        evict.add k
    for k in evict:
      self.mesh_cache.del k
      self.mesh_lru.del k
    info "frame mesh cache eviction",
      unit = self.model.id, evicted = evict.len, cached = self.mesh_cache.len
  self.mesh_cache[key] = mesh
  self.touch_cached(key)

proc cached_key(self: FramePlayer, index: int, chunk_id: Vector3): Option[Hash] =
  ## The chunk's key if it's been computed already — show's cheap steady-state
  ## skip check. Never computes.
  if index in self.keys and chunk_id in self.keys[index]:
    some(self.keys[index][chunk_id])
  else:
    none(Hash)

proc key_for(self: FramePlayer, index: int, chunk_id: Vector3): Hash =
  ## The chunk's content key, computed on first use inside the drain budget and
  ## memoized. Sealed builds key on the chunk's own bytes (borders always bake);
  ## unsealed builds key shell-aware, since the mesh borders depend on the
  ## frame's neighbor content.
  if index in self.keys and chunk_id in self.keys[index]:
    return self.keys[index][chunk_id]
  if self.model.sealed_frames:
    result =
      if chunk_id in self.model.frames[index].chunks:
        hash(self.model.frames[index].chunks[chunk_id].data)
      else:
        Hash(0)
  else:
    result = chunk_frame_key(
      self.decoded.mget_or_put(index, DecodedChunks()),
      self.model.frames[index],
      chunk_id,
    )
  self.keys.mget_or_put(index, Table[Vector3, Hash]())[chunk_id] = result

proc write_chunk(
    self: FramePlayer, chunk_id: Vector3, snapshot: SnapshotData, remesh: bool
) =
  fill_chunk_type_bytes(self.bytes, snapshot, self.resolver)
  discard self.terrain.set_block_voxel_data(chunk_id, self.bytes, remesh)
  self.dirty.incl chunk_id

proc drain(self: FramePlayer) =
  ## Apply queued frame chunks under a time budget. Big flips spread over
  ## several process ticks instead of stalling the game thread; playback can't
  ## advance until the queue and the miss set drain, so pacing is free — the
  ## animation just holds the frame a little longer.
  if self.queue.len == 0 or not ?self.renderer.voxel_tool:
    return
  const BUDGET_MS = 8
  let start = get_mono_time()
  let frames = self.model.frames
  flush_registry()
  var done: seq[Vector3]
  for chunk_id, chunk_index in self.queue:
    if chunk_index >= frames.len or chunk_id in self.missing:
      # a bake is already in flight for this chunk — let it land or time out
      # before writing newer content over it
      done.add chunk_id
      continue
    let target = self.key_for(chunk_index, chunk_id)
    if chunk_id notin self.display or self.display[chunk_id] != target:
      let frame = frames[chunk_index]
      self.missing.del chunk_id
      if chunk_id notin frame.chunks:
        self.write_chunk(chunk_id, SnapshotData(), remesh = false)
        self.staged[chunk_id] = nil
        self.display[chunk_id] = target
      elif target in self.mesh_cache:
        self.touch_cached(target)
        self.write_chunk(chunk_id, frame.chunks[chunk_id], remesh = false)
        self.staged[chunk_id] = self.mesh_cache[target]
        self.display[chunk_id] = target
      else:
        # bake from data: the padded payload carries the frame's own neighbor
        # shell (or air when sealed), so the bake is valid no matter what any
        # neighbor currently displays. The chunk keeps its previous MESH until
        # the bake lands, but its data is written now (mirroring the cache-hit
        # path): if the engine destroys and recreates this mesh block (viewer
        # churn), pairing remeshes it from data — empty data would blank a chunk
        # the display map already counts as shown, forever.
        self.write_chunk(chunk_id, frame.chunks[chunk_id], remesh = false)
        fill_padded_chunk_bytes(
          self.padded_bytes,
          self.decoded.mget_or_put(chunk_index, DecodedChunks()),
          frame,
          chunk_id,
          self.resolver,
          sealed = self.model.sealed_frames,
        )
        self.terrain.request_frame_mesh(chunk_id, self.padded_bytes, target.int64)
        self.missing[chunk_id] = (target, get_mono_time())
    done.add chunk_id
    if (get_mono_time() - start).in_milliseconds >= BUDGET_MS:
      break
  for chunk_id in done:
    self.queue.del chunk_id
  flush_registry()

proc viewer_positions(self: FramePlayer): seq[Vector3] =
  ## Paired viewers' positions in terrain-local voxel coordinates — players and
  ## agent bots alike, straight from the engine's pairing state
  ## (get_debug_paired_viewers appends a bounds entry; entries without a
  ## local_position key are skipped).
  let viewers = self.terrain.get_debug_paired_viewers()
  for i in 0 ..< viewers.len:
    let entry = viewers[i].as_dictionary
    let pos = entry["local_position"]
    if pos.get_type == VariantType.Vector3:
      result.add pos.as_vector3

proc effective_frame(
    self: FramePlayer, chunk_id: Vector3, index, count: int, viewers: seq[Vector3]
): int =
  ## The frame this chunk should display: `index` near a viewer, a quantized
  ## index mid-distance, frame 0 beyond. Quantized indices are just other
  ## content keys, so the cache, miss set and blocking playback need no special
  ## cases — distant chunks simply flip less.
  if count <= 1 or viewers.len == 0 or not frame_lod_enabled:
    return index
  let centre = chunk_id * ChunkDim.float + vec3(8, 8, 8)
  var nearest = float.high
  for viewer in viewers:
    let d = (viewer - centre).length
    if d < nearest:
      nearest = d
  let scale = max(self.model.scale, 0.001)
  let dist = nearest * scale # local voxels -> world metres
  if dist <= frame_lod_near:
    index
  elif dist <= frame_lod_mid:
    index - index mod frame_lod_mid_step
  else:
    0

proc show*(self: FramePlayer, index: int) =
  ## Queue the chunk work for frame `index`. Each loaded chunk picks an
  ## effective frame by distance (temporal LOD), then either matches what it
  ## already displays (skip) or joins the drain queue. The drain writes data and
  ## stages cached meshes; a miss bakes from data (see `drain`) and the chunk
  ## keeps its previous mesh until the bake lands — playback never blocks on
  ## meshing.
  let frames = self.model.frames
  if index < 0 or index >= frames.len or not ?self.renderer.voxel_tool:
    return
  let flip_start = get_mono_time()
  if index == 0 and self.commit_index != 0:
    # one line per animation loop: steady timestamps prove playback is
    # free-running (never gated on meshing)
    info "frame loop",
      unit = self.model.id, cached = self.mesh_cache.len, missing = self.missing.len
  self.commit_index = index
  let viewers = self.viewer_positions()
  var active: HashSet[int]
  active.incl index
  for chunk_id in self.loaded_chunks[]:
    let chunk_index = self.effective_frame(chunk_id, index, frames.len, viewers)
    active.incl chunk_index
    let known = self.cached_key(chunk_index, chunk_id)
    if known.is_some and chunk_id in self.display and self.display[chunk_id] == known.get:
      self.queue.del chunk_id
    else:
      self.queue[chunk_id] = chunk_index
  for cached_index in self.decoded.keys.to_seq:
    if cached_index notin active:
      self.decoded.del cached_index
  let flip_took = (get_mono_time() - flip_start).in_milliseconds
  if flip_took > 100:
    info "frame flip slow",
      unit = self.model.id, frame = index, ms = flip_took, queued = self.queue.len
  self.drain()

proc on_mesh_baked*(self: FramePlayer, chunk_id: Vector3, tag: int, mesh: Mesh) =
  ## A bake landed. It's a pure function of the padded bytes we submitted under
  ## this tag, so the mesh IS the tagged key's content — cache it
  ## unconditionally; the chunk joins the animation on its next flip. (nil is a
  ## valid mesh: an all-hole chunk bakes to nothing.)
  if chunk_id notin self.missing:
    return
  let entry = self.missing[chunk_id]
  if Hash(tag) != entry.key:
    return # superseded request (the chunk re-targeted); newer is coming
  if entry.key notin self.mesh_cache:
    inc self.new_keys
  self.store_cached(entry.key, mesh)
  if chunk_id notin self.display:
    # First appearance (fresh reload or a newly streamed chunk): show it the
    # moment its bake lands rather than waiting for a flip to re-queue it.
    # Deferral exists for flip atomicity BETWEEN frames — a chunk that has never
    # displayed isn't flipping, and a static chunk may only ever bake once, so
    # without this it can stay blank forever (missing island interiors on
    # reload). Chunks already displaying keep flipping atomically. Mark displayed
    # only if the mesh block existed (or there's nothing to show) — otherwise
    # leave it un-displayed so a later flip retries from the cache once the block
    # pairs.
    if self.terrain.set_block_mesh(chunk_id, mesh) or mesh.is_nil:
      self.display[chunk_id] = entry.key
  inc self.harvests
  self.missing.del chunk_id

proc commit_meshes(self: FramePlayer) =
  ## The visible half of a flip: swap every prepared mesh in one pass once the
  ## flip's queue has drained AND the displayed frame index has caught up to
  ## what was prepared (prepare-ahead builds the next flip during the current
  ## interval). Swaps are pointer assignments — a few ms even for thousands — so
  ## atomicity costs nothing. In-flight bakes don't hold the commit: their chunks
  ## stay stale until they land.
  if self.staged.len == 0 or self.queue.len > 0 or
      self.commit_index != self.model.current_frame:
    return
  for chunk_id, mesh in self.staged:
    discard self.terrain.set_block_mesh(chunk_id, mesh)
  self.staged.clear()
  # prepare the NEXT flip now: its keys and data writes spread over the rest of
  # the interval, so the flip itself is just the swap pass above
  if self.model.frames_fps > 0 and self.model.frames.len > 1:
    let current = self.model.current_frame
    var predicted = current + 1
    if predicted >= self.model.frames.len:
      predicted = if self.model.frames_loop: 0 else: current
    if predicted != current:
      self.show(predicted)

proc hide*(self: FramePlayer) =
  ## Drop all frame display and restore the live voxel state wherever frame
  ## content was written.
  self.missing.clear()
  self.display.clear()
  self.queue.clear()
  self.staged.clear()
  self.decoded.clear()
  if self.dirty.len > 0 and ?self.renderer.voxel_tool:
    for chunk_id in self.dirty:
      if chunk_id notin self.loaded_chunks[]:
        continue
      if chunk_id in self.model.voxels.packed_chunks:
        render_snapshot_replace(
          self.renderer.voxel_tool, chunk_id,
          self.model.voxels.packed_chunks[chunk_id], self.resolver,
        )
      else:
        erase_chunk_direct(self.renderer.voxel_tool, chunk_id)
      if chunk_id in self.model.voxels.chunk_deltas:
        let delta_seq = self.model.voxels.chunk_deltas[chunk_id]
        if ?delta_seq:
          for delta in delta_seq:
            render_delta_direct(
              self.renderer.voxel_tool, chunk_id, delta, self.resolver
            )
    flush_registry()
  self.dirty.clear()

proc render*(self: FramePlayer, index: int) =
  ## Display a saved frame (or the live state for index < 0). The terrain itself
  ## is the display: frame content is written into the voxel data, so collision
  ## and spatial queries always match what's on screen, and scaled builds animate
  ## correctly (the terrain inherits the node transform). Only SHOWING is gated
  ## on ASAP: hiding must always run — reset turns ASAP on before it clears
  ## current_frame, and skipping the hide there would leave stale frame content
  ## behind after the rerun.
  if index >= 0 and index < self.model.frames.len:
    if ASAP_MODE notin self.model.global_flags:
      self.show(index)
  else:
    self.hide()

proc on_frames_changed*(self: FramePlayer) =
  ## Frame content changed; the mesh cache stays valid (keys are content hashes)
  ## but per-frame key tables must recompute.
  self.keys.clear()
  self.decoded.clear()
  self.display.clear()
  self.render(self.model.current_frame)

proc reset*(self: FramePlayer) =
  ## A rerun always starts from live display, whatever was showing.
  self.hide()
  self.keys.clear()

proc drop_chunk*(self: FramePlayer, chunk_id: Vector3) =
  ## A chunk paged out: forget its frame bookkeeping.
  self.display.del chunk_id
  self.missing.del chunk_id
  self.queue.del chunk_id
  self.staged.del chunk_id
  self.dirty.excl chunk_id

proc tick*(self: FramePlayer) =
  ## Per-frame playback work: expire dropped bakes, drain the queue, commit a
  ## ready flip, and log stats. Called every process tick.
  if self.missing.len > 0:
    # a cancelled/dropped bake never signals; expire it so the chunk re-queues on
    # the next flip instead of staying stale forever
    let cutoff = get_mono_time() - init_duration(seconds = 5)
    var expired: seq[Vector3]
    for chunk_id, entry in self.missing:
      if entry.at < cutoff:
        expired.add chunk_id
    for chunk_id in expired:
      self.missing.del chunk_id
  self.drain()
  self.commit_meshes()

  if self.model.current_frame >= 0:
    let now = get_mono_time()
    if now > self.next_stats:
      self.next_stats = now + init_duration(seconds = 15)
      info "frame stats",
        unit = self.model.id,
        cached = self.mesh_cache.len,
        missing = self.missing.len,
        harvests = self.harvests,
        new_keys = self.new_keys
      self.harvests = 0
      self.new_keys = 0

  if self.model.frames_fps > 0 and not self.playback_logged:
    # One line per build: a playback that never swaps in (still warming, or too
    # big for the mesh cache) is visible in the logs.
    self.playback_logged = true
    info "frame playback",
      unit = self.model.id, frames = self.model.frames.len, fps = self.model.frames_fps

proc advance_playback*(self: FramePlayer) =
  ## Server-only: advance current_frame on the flipbook schedule. The synced
  ## current_frame then drives rendering on every side.
  ##
  ## Advance only when the displayed frame is fully meshed: at 8fps most chunks
  ## can't mesh inside one frame interval, and flipping early orphans the
  ## in-flight meshes. Free-running: chunks that aren't ready stay stale until
  ## their bake lands — playback never waits for meshing.
  if SERVER notin state.local_flags or self.model.frames_fps <= 0 or
      self.model.frames.len <= 1:
    return
  let now = get_mono_time()
  if now >= self.next_at:
    # absolute schedule: adding the interval to the previous deadline (not to
    # `now`) keeps the loop period exact instead of accruing per-flip processing
    # latency (~4% drift measured at 8fps)
    let interval = init_duration(milliseconds = int(1000.0 / self.model.frames_fps))
    self.next_at = self.next_at + interval
    if self.next_at < now:
      self.next_at = now + interval
    let last = self.model.frames.len - 1
    var next = self.model.current_frame + 1
    if next > last:
      if self.model.frames_loop:
        next = 0
      else:
        next = last
        self.model.frames_fps = 0.0
    self.model.current_frame = next
