import std/[tables, bitops, times, options, sets, hashes, algorithm]
import pkg/godot except print, Color
import
  godotapi/[
    node, spatial, voxel_terrain, voxel_mesher_blocky, voxel_mesher,
    voxel_tool, voxel_library, voxel_buffer, voxel_server, shader_material,
    resource_loader, packed_scene, ray_cast, mesh,
  ]
from std/os import get_env
import core, models/[things, builds, colors, voxels], gdutils
import ./queries, ./voxel_library_registry

const
  highlight_glow = 1.0
  default_glow = 0.0
  # Temporal LOD for frame playback, in world metres from the nearest
  # viewer: full frame rate inside NEAR, every MID_STEPth frame out to
  # MID, a static frame beyond. Distant waves are a few pixels tall, so
  # quantizing them is visually free — and it bounds the mesh cache by
  # the near disc instead of the whole loaded area (the 250m+ seas).
  frame_lod_near = 96.0
  frame_lod_mid = 160.0
  frame_lod_mid_step = 4
  error_flash_time = 0.5.seconds
  rgb_material_index = 6
    ## material/6: the shared vertex-color material static RGB voxels render
    ## with (materials 0..5 stay the uniform-tinted named colors).

# Temporal-LOD switch, read once at load. ENU_FRAME_LOD=0 disables it so every
# chunk animates at full rate regardless of distance — for A/B perf testing the
# LOD savings against the seal cost.
let frame_lod_enabled = get_env("ENU_FRAME_LOD", "1") != "0"

# Material iteration reads the terrain node's own slots (bounded by the
# engine's MAX_MATERIALS = 8), never the (dynamically growing) library and
# never shared.materials — the node's assignments are the ground truth for
# what's rendering, whatever the Shared has been through.
template each_material(self, i, m, body: untyped) =
  for i in 0 .. 7:
    let m = self.get_material(i).as(ShaderMaterial)
    if not ?m:
      break
    body

var build_scene {.threadvar.}: PackedScene
var shader {.threadvar.}: Shader
var hidden_shader {.threadvar.}: Shader
var rgb_shader {.threadvar.}: Shader
var hidden_rgb_shader {.threadvar.}: Shader

gdobj BuildNode of VoxelTerrain:
  var
    model* {.cursor.}: Build
    resolver: ColorIndexResolver
    transform_zid: EID
    # A model transform change is recorded here and applied in physics_process,
    # not in the watch (which fires on the render tick), so the node moves on the
    # same 60Hz tick as riders read it — smooth riding. Only set on a real model
    # change, so it never overwrites a node-side edit (those sync node->model in
    # process, with the watch paused).
    pending_transform: Option[Transform]
    positioned: bool # initial placement applied? (see the transform watch)
    default_view_distance: int
    toggle_error_highlight_at = MonoTime.high
    error_highlight_on: bool
    loaded_chunks: HashSet[Vector3]
    tracked_delta_seqs: Table[Vector3, EID]
    renderer: VoxelRenderer
    paging_logged: bool
    data_logged: bool
    holding_bakes: bool
    next_frame_at: MonoTime
    # Frame display: applying a frame writes the chunk's voxel data the way
    # any edit would. A chunk whose content key has a cached mesh gets it
    # set directly (write suppresses remeshing); a miss meshes through the
    # engine's normal pipeline. Playback advances only when the displayed
    # frame has no outstanding misses AND the terrain's mesh pipeline has
    # drained — at that instant every missed block's mesh was provably
    # built from the current frame's data, so the harvest into the cache
    # can't misattribute.
    frame_mesh_cache: Table[Hash, Mesh]
    frame_display: Table[Vector3, Hash] # content key shown per chunk
    frame_missing: Table[Vector3, tuple[key: Hash, at: MonoTime]]
      ## in-flight bakes: chunk -> the content key the bake was requested
      ## for, and when. Bakes are pure functions of the padded bytes we
      ## submit (request_frame_mesh), so the returned mesh IS the key's
      ## content — no attribution gating. A chunk in here keeps its
      ## previous mesh (stale, never a hole — the solid layer) and is
      ## skipped by the drain until its bake lands or times out; everything
      ## else keeps animating.
    frame_queue: Table[Vector3, int] # chunk -> frame index to apply
    frame_commit: Table[Vector3, Mesh]
      ## prepared mesh swaps, held until the whole flip is ready. Data
      ## writes and key work drain incrementally, but the visible change
      ## is one atomic pass — chunks never flip at different times.
    frame_padded_bytes: PoolByteArray # request_frame_mesh payload scratch
    frame_commit_index: int
      ## which flip the commit table was prepared for. Prepare-ahead
      ## builds the NEXT flip during the current interval; the commit
      ## waits until current_frame catches up, so cadence stays exact.
    frame_decoded: Table[int, DecodedChunks]
      ## lazily decoded chunks per frame index — the working set for
      ## per-chunk key computation inside the drain budget. Pruned each
      ## flip to the indexes still being applied.
      ## chunk applies pending for the displayed frame. show_frame only
      ## decides; drain_frame_queue does the writes under a per-tick time
      ## budget, so a 250m flip can't stall the game thread (the blocking
      ## playback gate simply waits for the queue to empty).
    frame_keys: Table[int, Table[Vector3, Hash]] # per frame, lazily built
    frame_bytes: PoolByteArray # reusable set_block_voxel_data payload
    frame_dirty: HashSet[Vector3] # terrain data differs from live state
    frame_mesh_lru: Table[Hash, int] # last-touched tick per cached mesh
    frame_lru_tick: int
    frame_harvests: int # since the last stats log
    frame_new_keys: int
    next_frame_stats: MonoTime
    playback_logged: bool
    next_warm_log: MonoTime

  proc init*() =
    self.bind_signals self, "block_loaded", "block_unloaded",
      "frame_mesh_baked"
    self.default_view_distance = self.max_view_distance.int

  proc prepare_materials() =
    let start = get_mono_time()
    if self.model.shared.materials.len == 0:
      for i in 0 .. int.high:
        let m = self.get_material(i)
        if not ?m:
          break
        else:
          let m = m.duplicate.as(ShaderMaterial)
          m.set_shader_param("emission_energy", default_glow.to_variant)
          self.model.shared.emission_colors.add(
            m.get_shader_param("emission").as_color
          )

          self.model.shared.materials.add(m)

    for i, material in self.model.shared.materials:
      self.set_material(i, material)
    let took = (get_mono_time() - start).in_milliseconds
    if took > 5:
      warn "prepare_materials slow", ms = took, unit = self.model.id

  proc watch_delta_seq(chunk_id: Vector3, delta_seq: EdSeq[DeltaUpdate]) =
    if chunk_id in self.tracked_delta_seqs:
      return

    let zid = delta_seq.watch:
      if added and chunk_id in self.loaded_chunks:
        var painted = 0
        if ASAP_MODE in self.model.global_flags:
          painted = self.renderer.buffer_delta(chunk_id, change.item)
        elif ?self.renderer.voxel_tool:
          painted = render_delta_direct(
            self.renderer.voxel_tool, chunk_id, change.item, self.resolver
          )
          flush_registry()
        self.model.rendered_voxel_count =
          self.model.rendered_voxel_count + painted

    self.tracked_delta_seqs[chunk_id] = zid

  proc set_glow(glow: float) =
    self.each_material(i, m):
      m.set_shader_param("emission_energy", glow.to_variant)

  proc set_highlight() =
    self.each_material(i, m):
      if self.error_highlight_on:
        m.set_shader_param("emission", ACTION_COLORS[RED].to_variant)
      elif i < self.model.shared.emission_colors.len:
        m.set_shader_param(
          "emission", self.model.shared.emission_colors[i].to_variant
        )

      if HIGHLIGHT in self.model.local_flags or
          (
            HIGHLIGHT_ERROR in self.model.global_flags and
            self.error_highlight_on
          ):
        m.set_shader_param("emission_energy", highlight_glow.to_variant)
      else:
        m.set_shader_param("emission_energy", self.model.glow.to_variant)

  proc set_visibility() =
    if VISIBLE in self.model.global_flags:
      self.visible = true

      self.each_material(i, material):
        material.shader =
          if i == rgb_material_index: rgb_shader else: shader
    elif VISIBLE notin self.model.global_flags and GOD in state.local_flags:
      self.visible = true

      self.each_material(i, material):
        material.shader =
          if i == rgb_material_index: hidden_rgb_shader else: hidden_shader
    else:
      self.visible = false

  proc touch_cached(key: Hash) =
    inc self.frame_lru_tick
    self.frame_mesh_lru[key] = self.frame_lru_tick

  proc store_cached(key: Hash, mesh: Mesh) =
    ## Insert with LRU batch eviction — never a wholesale clear: dropping
    ## the whole cache mid-playback restarts the mesh churn from zero (the
    ## misses re-paste and re-mesh ~everything, every flip, forever).
    const max_cached = 65536
    if self.frame_mesh_cache.len >= max_cached:
      var stamps = new_seq[int](self.frame_mesh_lru.len)
      var i = 0
      for _, stamp in self.frame_mesh_lru:
        stamps[i] = stamp
        inc i
      stamps.sort()
      let cutoff = stamps[stamps.len div 4] # oldest quarter goes
      var evict: seq[Hash]
      for k, stamp in self.frame_mesh_lru:
        if stamp <= cutoff:
          evict.add k
      for k in evict:
        self.frame_mesh_cache.del k
        self.frame_mesh_lru.del k
      info "frame mesh cache eviction",
        unit = self.model.id,
        evicted = evict.len,
        cached = self.frame_mesh_cache.len
    self.frame_mesh_cache[key] = mesh
    self.touch_cached(key)

  proc cached_key(index: int, chunk_id: Vector3): Option[Hash] =
    ## The chunk's key if it's been computed already — show_frame's cheap
    ## steady-state skip check. Never computes.
    if index in self.frame_keys and chunk_id in self.frame_keys[index]:
      some(self.frame_keys[index][chunk_id])
    else:
      none(Hash)

  proc key_for(index: int, chunk_id: Vector3): Hash =
    ## The chunk's content key, computed on first use inside the drain
    ## budget and memoized. Sealed builds key on the chunk's own bytes
    ## (borders always bake); unsealed builds key shell-aware, since the
    ## mesh borders depend on the frame's neighbor content.
    if index in self.frame_keys and chunk_id in self.frame_keys[index]:
      return self.frame_keys[index][chunk_id]
    if self.model.sealed_frames:
      result =
        if chunk_id in self.model.frames[index].chunks:
          hash(self.model.frames[index].chunks[chunk_id].data)
        else:
          Hash(0)
    else:
      result = chunk_frame_key(
        self.frame_decoded.mget_or_put(index, DecodedChunks()),
        self.model.frames[index],
        chunk_id,
      )
    self.frame_keys.mget_or_put(index, Table[Vector3, Hash]())[chunk_id] =
      result

  proc write_frame_chunk(
      chunk_id: Vector3, snapshot: SnapshotData, remesh: bool
  ) =
    fill_chunk_type_bytes(self.frame_bytes, snapshot, self.resolver)
    discard self.set_block_voxel_data(chunk_id, self.frame_bytes, remesh)
    self.frame_dirty.incl chunk_id

  proc drain_frame_queue() =
    ## Apply queued frame chunks under a time budget. Big flips spread over
    ## several process ticks instead of stalling the game thread; playback
    ## can't advance until the queue and the miss set drain, so pacing is
    ## free — the animation just holds the frame a little longer.
    if self.frame_queue.len == 0 or not ?self.renderer.voxel_tool:
      return
    const BUDGET_MS = 8
    let start = get_mono_time()
    let frames = self.model.frames
    flush_registry()
    var done: seq[Vector3]
    for chunk_id, chunk_index in self.frame_queue:
      if chunk_index >= frames.len or chunk_id in self.frame_missing:
        # a bake is already in flight for this chunk — let it land or
        # time out before writing newer content over it
        done.add chunk_id
        continue
      let target = self.key_for(chunk_index, chunk_id)
      if chunk_id notin self.frame_display or
          self.frame_display[chunk_id] != target:
        let frame = frames[chunk_index]
        self.frame_missing.del chunk_id
        if chunk_id notin frame.chunks:
          self.write_frame_chunk(chunk_id, SnapshotData(), remesh = false)
          self.frame_commit[chunk_id] = nil
          self.frame_display[chunk_id] = target
        elif target in self.frame_mesh_cache:
          self.touch_cached(target)
          self.write_frame_chunk(
            chunk_id, frame.chunks[chunk_id], remesh = false
          )
          self.frame_commit[chunk_id] = self.frame_mesh_cache[target]
          self.frame_display[chunk_id] = target
        else:
          # bake from data: the padded payload carries the frame's own
          # neighbor shell (or air when sealed), so the bake is valid no
          # matter what any neighbor currently displays. The chunk keeps its
          # previous MESH until the bake lands, but its data is written now
          # (mirroring the cache-hit path): if the engine destroys and
          # recreates this mesh block (viewer churn), pairing remeshes it
          # from data — empty data would blank a chunk the display map
          # already counts as shown, forever.
          self.write_frame_chunk(
            chunk_id, frame.chunks[chunk_id], remesh = false
          )
          fill_padded_chunk_bytes(
            self.frame_padded_bytes,
            self.frame_decoded.mget_or_put(chunk_index, DecodedChunks()),
            frame,
            chunk_id,
            self.resolver,
            sealed = self.model.sealed_frames,
          )
          self.request_frame_mesh(
            chunk_id, self.frame_padded_bytes, target.int64
          )
          self.frame_missing[chunk_id] = (target, get_mono_time())
      done.add chunk_id
      if (get_mono_time() - start).in_milliseconds >= BUDGET_MS:
        break
    for chunk_id in done:
      self.frame_queue.del chunk_id
    flush_registry()

  proc viewer_positions(): seq[Vector3] =
    ## Paired viewers' positions in terrain-local voxel coordinates —
    ## players and agent bots alike, straight from the engine's pairing
    ## state (get_debug_paired_viewers appends a bounds entry; entries
    ## without a local_position key are skipped).
    let viewers = self.get_debug_paired_viewers()
    for i in 0 ..< viewers.len:
      let entry = viewers[i].as_dictionary
      let pos = entry["local_position"]
      if pos.get_type == VariantType.Vector3:
        result.add pos.as_vector3

  proc effective_frame(
      chunk_id: Vector3, index, count: int, viewers: seq[Vector3]
  ): int =
    ## The frame this chunk should display: `index` near a viewer, a
    ## quantized index mid-distance, frame 0 beyond. Quantized indices are
    ## just other content keys, so the cache, miss set and blocking
    ## playback need no special cases — distant chunks simply flip less.
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

  proc show_frame(index: int) =
    ## Queue the chunk work for frame `index`. Each loaded chunk picks an
    ## effective frame by distance (temporal LOD), then either matches what
    ## it already displays (skip) or joins the drain queue. The drain writes
    ## data and stages cached meshes; a miss bakes from data (see
    ## `drain_frame_queue`) and the chunk keeps its previous mesh until the
    ## bake lands — playback never blocks on meshing.
    let frames = self.model.frames
    if index < 0 or index >= frames.len or not ?self.renderer.voxel_tool:
      return
    let flip_start = get_mono_time()
    if index == 0 and self.frame_commit_index != 0:
      # one line per animation loop: steady timestamps prove playback is
      # free-running (never gated on meshing)
      info "frame loop",
        unit = self.model.id,
        cached = self.frame_mesh_cache.len,
        missing = self.frame_missing.len
    self.frame_commit_index = index
    let viewers = self.viewer_positions()
    var active: HashSet[int]
    active.incl index
    for chunk_id in self.loaded_chunks:
      let chunk_index =
        self.effective_frame(chunk_id, index, frames.len, viewers)
      active.incl chunk_index
      let known = self.cached_key(chunk_index, chunk_id)
      if known.is_some and chunk_id in self.frame_display and
          self.frame_display[chunk_id] == known.get:
        self.frame_queue.del chunk_id
      else:
        self.frame_queue[chunk_id] = chunk_index
    for cached_index in self.frame_decoded.keys.to_seq:
      if cached_index notin active:
        self.frame_decoded.del cached_index
    let flip_took = (get_mono_time() - flip_start).in_milliseconds
    if flip_took > 100:
      info "frame flip slow",
        unit = self.model.id,
        frame = index,
        ms = flip_took,
        queued = self.frame_queue.len
    self.drain_frame_queue()

  method on_frame_mesh_baked(chunk_id: Vector3, tag: int, mesh: Mesh) =
    ## A bake landed. It's a pure function of the padded bytes we submitted
    ## under this tag, so the mesh IS the tagged key's content — cache it
    ## unconditionally; the chunk joins the animation on its next flip.
    ## (nil is a valid mesh: an all-hole chunk bakes to nothing.)
    if not ?self.model or chunk_id notin self.frame_missing:
      return
    let entry = self.frame_missing[chunk_id]
    if Hash(tag) != entry.key:
      return # superseded request (the chunk re-targeted); newer is coming
    if entry.key notin self.frame_mesh_cache:
      inc self.frame_new_keys
    self.store_cached(entry.key, mesh)
    if chunk_id notin self.frame_display:
      # First appearance (fresh reload or a newly streamed chunk): show it the
      # moment its bake lands rather than waiting for a flip to re-queue it.
      # Deferral exists for flip atomicity BETWEEN frames — a chunk that has
      # never displayed isn't flipping, and a static chunk may only ever bake
      # once, so without this it can stay blank forever (missing island
      # interiors on reload). Chunks already displaying keep flipping atomically.
      # Mark displayed only if the mesh block existed (or there's nothing to
      # show) — otherwise leave it un-displayed so a later flip retries from
      # the cache once the block pairs.
      if self.set_block_mesh(chunk_id, mesh) or mesh.is_nil:
        self.frame_display[chunk_id] = entry.key
    inc self.frame_harvests
    self.frame_missing.del chunk_id

  proc commit_frame_meshes() =
    ## The visible half of a flip: swap every prepared mesh in one pass
    ## once the flip's queue has drained AND the displayed frame index has
    ## caught up to what was prepared (prepare-ahead builds the next flip
    ## during the current interval). Swaps are pointer assignments — a few
    ## ms even for thousands — so atomicity costs nothing. In-flight bakes
    ## don't hold the commit: their chunks stay stale until they land.
    if self.frame_commit.len == 0 or self.frame_queue.len > 0 or
        self.frame_commit_index != self.model.current_frame:
      return
    for chunk_id, mesh in self.frame_commit:
      discard self.set_block_mesh(chunk_id, mesh)
    self.frame_commit.clear()
    # prepare the NEXT flip now: its keys and data writes spread over the
    # rest of the interval, so the flip itself is just the swap pass above
    if self.model.frames_fps > 0 and self.model.frames.len > 1:
      let current = self.model.current_frame
      var predicted = current + 1
      if predicted >= self.model.frames.len:
        predicted = if self.model.frames_loop: 0 else: current
      if predicted != current:
        self.show_frame(predicted)

  proc hide_frames() =
    self.frame_missing.clear()
    self.frame_display.clear()
    self.frame_queue.clear()
    self.frame_commit.clear()

    self.frame_decoded.clear()
    if self.frame_dirty.len > 0 and ?self.renderer.voxel_tool:
      # restore the live voxel state wherever frame content was written
      for chunk_id in self.frame_dirty:
        if chunk_id notin self.loaded_chunks:
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
    self.frame_dirty.clear()

  proc render_frame(index: int) =
    ## Display a saved frame (or the live state for index < 0). The terrain
    ## itself is the display: frame content is written into the voxel data,
    ## so collision and spatial queries always match what's on screen, and
    ## scaled builds animate correctly (the terrain inherits the node
    ## transform). Only SHOWING is gated on ASAP: hiding must always run —
    ## reset turns ASAP on before it clears current_frame, and skipping the
    ## hide there would leave stale frame content behind after the rerun.
    if index >= 0 and index < self.model.frames.len:
      if ASAP_MODE notin self.model.global_flags:
        self.show_frame(index)
    else:
      self.hide_frames()

  method on_block_loaded(chunk_id: Vector3) =
    let start = get_mono_time()
    if ?self.model:
      self.loaded_chunks.incl(chunk_id)

      if SERVER notin state.local_flags:
        # Voxel paging: the engine's view streaming is the demand signal. A
        # block entering view pulls its chunk data from the server (no-op if
        # already loaded; a miss leaves a per-key subscription behind, so
        # someone building here pops in). The tables are LAZY — they arrive
        # as empty handles with the thing.
        self.model.voxels.packed_chunks.request(chunk_id)
        self.model.voxels.chunk_deltas.request(chunk_id)
        if not self.paging_logged:
          self.paging_logged = true
          # One line per build: paired with "voxel data arriving" below, a
          # build that requests but never receives is visible in the logs.
          info "voxel paging", thing = self.model.id

      # While a frame is displayed, don't paint the live state into the
      # fresh chunk — show_frame below writes the frame's content instead,
      # and a live paint would schedule a remesh that lands after (and
      # overwrites) a directly-set cached frame mesh. The live state comes
      # back through hide_frames, which replays it for every dirty chunk.
      let displaying_frame =
        self.model.current_frame >= 0 and
        self.model.current_frame < self.model.frames.len and
        ASAP_MODE notin self.model.global_flags

      if chunk_id in self.model.voxels.packed_chunks and not displaying_frame:
        let snapshot = self.model.voxels.packed_chunks[chunk_id]
        var painted = 0
        if ASAP_MODE in self.model.global_flags:
          painted = self.renderer.buffer_snapshot(chunk_id, snapshot)
        elif ?self.renderer.voxel_tool:
          painted = render_snapshot_direct(
            self.renderer.voxel_tool, chunk_id, snapshot, self.resolver
          )
        self.model.rendered_voxel_count =
          self.model.rendered_voxel_count + painted

      if chunk_id in self.model.voxels.chunk_deltas:
        let delta_seq = self.model.voxels.chunk_deltas[chunk_id]
        if ?delta_seq:
          if not displaying_frame:
            var painted = 0
            for delta in delta_seq:
              if ASAP_MODE in self.model.global_flags:
                painted = painted + self.renderer.buffer_delta(chunk_id, delta)
              elif ?self.renderer.voxel_tool:
                painted = painted + render_delta_direct(
                  self.renderer.voxel_tool, chunk_id, delta, self.resolver
                )
            if painted > 0:
              self.model.rendered_voxel_count =
                self.model.rendered_voxel_count + painted

          self.watch_delta_seq(chunk_id, delta_seq)
      flush_registry()
      if displaying_frame:
        # give the fresh chunk its frame content (cheap for the rest:
        # display-key checks make the loop a no-op elsewhere)
        self.show_frame(self.model.current_frame)
      let took = (get_mono_time() - start).in_milliseconds
      if took > 10:
        warn "on_block_loaded slow", ms = took, unit = self.model.id

  method on_block_unloaded(chunk_id: Vector3) =
    if ?self.model:
      self.loaded_chunks.excl(chunk_id)
      if SERVER notin state.local_flags:
        # Out of view: page out. Evicts locally (the excl above keeps the
        # REMOVED watch from erasing an already-dropped block) and retracts
        # our per-key interest upstream — never touches the authority's data.
        self.model.voxels.packed_chunks.release(chunk_id)
        self.model.voxels.chunk_deltas.release(chunk_id)
      self.frame_display.del chunk_id
      self.frame_missing.del chunk_id
      self.frame_queue.del chunk_id
      self.frame_commit.del chunk_id
      self.frame_dirty.excl chunk_id

  proc track_changes() =
    self.model.glow_value.watch:
      if added:
        self.set_glow(change.item)

    self.bounds = self.model.bounds
    self.model.bounds_value.watch:
      if added:
        notice "changing bounds", new = change.item, id = self.model.id
        self.bounds = change.item

    # Watch packed_chunks for new snapshots
    self.model.voxels.packed_chunks.watch:
      if added:
        if not self.data_logged:
          self.data_logged = true
          info "voxel data arriving", thing = self.model.id
        if change.item.key in self.loaded_chunks:
          # A rewrite (REMOVED+MODIFIED, e.g. voxels.clear() + redraw
          # coalescing in one sync batch) must REPLACE the chunk: painting
          # it additively leaves voxels the new content doesn't cover —
          # visible as stray geometry at the edges of regenerated builds.
          if ASAP_MODE in self.model.global_flags:
            self.renderer.buffer_snapshot(
              change.item.key, change.item.value, replace = modified
            )
          elif ?self.renderer.voxel_tool:
            if modified:
              render_snapshot_replace(
                self.renderer.voxel_tool, change.item.key, change.item.value,
                self.resolver,
              )
            else:
              render_snapshot_direct(
                self.renderer.voxel_tool, change.item.key, change.item.value,
                self.resolver,
              )
      elif removed and not modified:
        # Paged out or cleared (a rewrite is REMOVED+MODIFIED and skipped) —
        # clear it from the terrain, and from the ASAP buffer's terrain
        # copy so the next paste can't resurrect it.
        if change.item.key in self.loaded_chunks and ?self.renderer.voxel_tool:
          self.renderer.buffer_erase(change.item.key)
          erase_chunk_direct(self.renderer.voxel_tool, change.item.key)

    # Render existing packed_chunks (for clients connecting to existing builds)
    if ?self.renderer.voxel_tool:
      let start = get_mono_time()
      for chunk_id, snapshot in self.model.voxels.packed_chunks:
        if chunk_id in self.loaded_chunks:
          render_snapshot_direct(
            self.renderer.voxel_tool, chunk_id, snapshot, self.resolver
          )
      flush_registry()
      let took = (get_mono_time() - start).in_milliseconds
      if took > 10:
        warn "initial snapshot render slow", ms = took, unit = self.model.id

    # Watch chunk_deltas for new chunks
    self.model.voxels.chunk_deltas.watch:
      if added:
        let chunk_id = change.item.key
        let delta_seq = change.item.value
        if ?delta_seq:
          # Render any existing deltas in the new chunk
          if chunk_id in self.loaded_chunks:
            for delta in delta_seq:
              if ASAP_MODE in self.model.global_flags:
                self.renderer.buffer_delta(chunk_id, delta)
              elif ?self.renderer.voxel_tool:
                render_delta_direct(
                  self.renderer.voxel_tool, chunk_id, delta, self.resolver
                )
            flush_registry()
          # Watch for future deltas
          self.watch_delta_seq(chunk_id, delta_seq)
      elif removed:
        let chunk_id = change.item.key
        if chunk_id in self.tracked_delta_seqs:
          Ed.thread_ctx.untrack(self.tracked_delta_seqs[chunk_id])
          self.tracked_delta_seqs.del(chunk_id)
        if not modified and chunk_id notin self.model.voxels.packed_chunks and
            chunk_id in self.loaded_chunks and ?self.renderer.voxel_tool:
          # Paged out a delta-only chunk (never snapshotted): the packed_chunks
          # REMOVED won't fire for it, so erase here.
          self.renderer.buffer_erase(chunk_id)
          erase_chunk_direct(self.renderer.voxel_tool, chunk_id)

    # Render existing chunk_deltas and set up watches
    if ?self.renderer.voxel_tool:
      let start = get_mono_time()
      for chunk_id, delta_seq in self.model.voxels.chunk_deltas:
        if ?delta_seq:
          if chunk_id in self.loaded_chunks:
            for delta in delta_seq:
              render_delta_direct(
                self.renderer.voxel_tool, chunk_id, delta, self.resolver
              )
          self.watch_delta_seq(chunk_id, delta_seq)
      flush_registry()
      let took = (get_mono_time() - start).in_milliseconds
      if took > 10:
        warn "initial delta render slow", ms = took, unit = self.model.id

    self.model.global_flags.watch:
      if (
        change.item == VISIBLE and
        SCRIPT_INITIALIZING notin self.model.global_flags
      ) or SCRIPT_INITIALIZING.removed:
        self.set_visibility
      elif RESETTING.added:
        # a rerun always starts from live display, whatever was showing
        self.hide_frames()
        self.frame_keys.clear()
        self.loaded_chunks.clear()
        self.generator = nil
        self.stream = nil
      elif RESETTING.removed:
        self.generator = gdnew[VoxelGeneratorFlat]()
      elif HIGHLIGHT_ERROR.added:
        self.toggle_error_highlight_at = get_mono_time() + error_flash_time
        self.error_highlight_on = true
        self.set_highlight
      elif HIGHLIGHT_ERROR.removed:
        self.toggle_error_highlight_at = MonoTime.high
        self.error_highlight_on = false
        self.set_highlight
      elif change.item == ASAP_MODE:
        if added:
          self.renderer.begin_asap()
          # Only external (EPHEMERAL) streams hold bakes: script builds cycle
          # ASAP forever (looping rebuilds) and would wedge the refcount, and
          # they draw named colors that need no bake anyway.
          if EPHEMERAL in self.model.global_flags and not self.holding_bakes:
            self.holding_bakes = true
            hold_bakes()
        elif removed:
          # One bake for everything the ASAP stream registered, landing with
          # the final paste. Interim periodic pastes may briefly mesh new
          # static colors as air; this remesh corrects them.
          self.renderer.end_asap()
          if self.holding_bakes:
            self.holding_bakes = false
            release_bakes()
          flush_registry()

    self.model.local_flags.watch:
      if change.item == HIGHLIGHT:
        self.set_highlight

    state.local_flags.watch:
      if change.item == GOD:
        self.set_visibility

    self.model.current_frame_value.watch:
      if added:
        self.render_frame(change.item)

    self.model.frames.watch:
      if added or removed:
        # frame content changed; the mesh cache stays valid (keys are
        # content hashes) but per-frame key tables must recompute
        self.frame_keys.clear()
        self.frame_decoded.clear()
        self.frame_display.clear()
        self.render_frame(self.model.current_frame)

    self.model.cull_down_faces_value.watch:
      if added:
        self.set_cull_down_faces(change.item)

    self.model.scale_value.watch:
      if added:
        # Scale lives in the model's transform.basis (set synchronously by
        # `scale=`); the node picks it up via transform_value below. Here we
        # adjust view distances for the new scale: max_view_distance caps
        # the terrain's own streaming, and viewer_distance_scale extends
        # each viewer's pairing range to cover the same WORLD distance —
        # without it, meshes on a 0.5-scale build stop at half the world
        # range the viewer asked for, leaving a visible ring of loaded but
        # never-meshed blocks (and stranding stale meshes) at the fringe.
        self.max_view_distance =
          int(self.default_view_distance.float / change.item)
        self.set_viewer_distance_scale(1.0 / change.item)

    self.transform_zid = self.model.transform_value.watch:
      if added:
        if self.positioned:
          self.pending_transform = some(change.item)
        else:
          # Apply the initial placement immediately so the build doesn't flash at
          # the origin for a frame; later (movement) changes defer to the physics
          # tick for smooth riding.
          self.transform = change.item
          self.positioned = true

    self.model.sight_query_value.watch:
      if added:
        var query = change.item
        let collision_layer = self.collision_layer
        self.collision_layer = 0
        query.run(self.model)
        self.collision_layer = collision_layer
        self.model.sight_query = query

  method exit_tree() =
    if self.holding_bakes:
      self.holding_bakes = false
      release_bakes()
      flush_registry()

  method physics_process(delta: float) =
    # Apply a recorded model transform on the physics tick, so a rider reading us
    # in its own physics_process samples a value that advanced on the same 60Hz
    # tick — no render-vs-physics jitter. Cleared after applying so it can't
    # overwrite a later node-side edit.
    if self.pending_transform.is_some:
      self.transform = self.pending_transform.get
      self.pending_transform = none(Transform)

  method process(delta: float) =
    if ?self.model:
      # Sync node->model only when the script isn't driving us this frame. While a
      # model->node update is pending (applied next physics_process), the node is
      # a frame stale, so writing it back would fight the script and bounce. With
      # no pending, this still carries node-side edits to the model.
      if self.model.code.owner == state.worker_ctx_name and
          self.pending_transform.is_none:
        self.model.transform_value.pause self.transform_zid:
          self.model.transform = self.transform

      if get_mono_time() > self.toggle_error_highlight_at:
        self.error_highlight_on = not self.error_highlight_on
        self.toggle_error_highlight_at = get_mono_time() + error_flash_time
        self.set_highlight()

      # Frame playback: the server is the single advancing authority; the
      # synced current_frame drives rendering on every side. Each side
      # harvests its own miss set once its mesh pipeline drains.
      if self.frame_missing.len > 0:
        # a cancelled/dropped bake never signals; expire it so the chunk
        # re-queues on the next flip instead of staying stale forever
        let cutoff = get_mono_time() - init_duration(seconds = 5)
        var expired: seq[Vector3]
        for chunk_id, entry in self.frame_missing:
          if entry.at < cutoff:
            expired.add chunk_id
        for chunk_id in expired:
          self.frame_missing.del chunk_id
      self.drain_frame_queue()
      self.commit_frame_meshes()

      if self.model.current_frame >= 0:
        let now2 = get_mono_time()
        if now2 > self.next_frame_stats:
          self.next_frame_stats = now2 + init_duration(seconds = 15)
          info "frame stats",
            unit = self.model.id,
            cached = self.frame_mesh_cache.len,
            missing = self.frame_missing.len,
            harvests = self.frame_harvests,
            new_keys = self.frame_new_keys
          self.frame_harvests = 0
          self.frame_new_keys = 0

      if self.model.frames_fps > 0 and not self.playback_logged:
        # One line per build: paired with "frames showing" below, a playback
        # that never swaps in (still warming, or too big for the mesh cache)
        # is visible in the logs.
        self.playback_logged = true
        info "frame playback",
          unit = self.model.id,
          frames = self.model.frames.len,
          fps = self.model.frames_fps

      # Advance only when the displayed frame is fully meshed: at 8fps most
      # chunks can't mesh inside one frame interval, and flipping early
      # orphans the in-flight meshes — the warm-up would never converge.
      # free-running: chunks that aren't ready stay stale until their bake
      # lands — playback never waits for meshing
      if SERVER in state.local_flags and self.model.frames_fps > 0 and
          self.model.frames.len > 1:
        let now = get_mono_time()
        if now >= self.next_frame_at:
          # absolute schedule: adding the interval to the previous deadline
          # (not to `now`) keeps the loop period exact instead of accruing
          # per-flip processing latency (~4% drift measured at 8fps)
          let interval =
            init_duration(milliseconds = int(1000.0 / self.model.frames_fps))
          self.next_frame_at = self.next_frame_at + interval
          if self.next_frame_at < now:
            self.next_frame_at = now + interval
          let last = self.model.frames.len - 1
          var next = self.model.current_frame + 1
          if next > last:
            if self.model.frames_loop:
              next = 0
            else:
              next = last
              self.model.frames_fps = 0.0
          self.model.current_frame = next

      let is_local = self.model.code.owner == state.worker_ctx_name
      let tick_start = get_mono_time()
      self.renderer.tick(is_local)
      flush_registry()
      let tick_took = (get_mono_time() - tick_start).in_milliseconds
      if tick_took > 10:
        warn "renderer tick slow", ms = tick_took, unit = self.model.id

      if is_local:
        # Terrain pipeline backlog, plus 1 while the ASAP renderer holds a
        # buffered paste the terrain hasn't seen yet.
        var pending = int(self.get_pending_block_updates())
        if self.renderer.dirty:
          pending.inc
        if pending != self.model.pending_block_updates:
          self.model.pending_block_updates = pending

  proc setup*() =
    let was_skipping_join = dont_join
    dont_join = true

    self.model.init_voxels_if_needed()

    # Static RGB colors resolve through the process-global library registry;
    # named indices pass through untouched (identity below STATIC_COLOR_BASE).
    set_registry_library(self.mesher.as(VoxelMesherBlocky).library)
    let model = self.model
    self.resolver = proc(color_index: int): int64 =
      slot_for(resolve_color(model.shared, color_index))

    # Pre-register the build's whole palette (it syncs with the unit and
    # lists every static color the build will ever render), so a block
    # loading into view later never mints — and bakes — a new library entry.
    if ?self.model.shared:
      for color in self.model.shared.palette:
        discard slot_for(color)
      self.model.shared.palette.watch:
        if added:
          discard slot_for(change.item)
      flush_registry() # no-op while an ephemeral stream holds bakes

    # Create renderer for ASAP mode buffer operations
    self.renderer = VoxelRenderer.init(self.get_voxel_tool(), self.resolver)

    self.frame_bytes = new_pool_byte_array()
    self.frame_bytes.set_len(CHUNK_VOLUME * 2)
    self.frame_padded_bytes = new_pool_byte_array()
    self.frame_padded_bytes.set_len(
      (ChunkDim + 2) * (ChunkDim + 2) * (ChunkDim + 2) * 2
    )

    # Builds default to ASAP, so the flag is usually set before this node
    # exists — the ASAP_MODE.added watch never fires for it. Adopt the
    # current state here; the watch handles later transitions.
    if ASAP_MODE in self.model.global_flags:
      self.renderer.begin_asap()
      if EPHEMERAL in self.model.global_flags and not self.holding_bakes:
        self.holding_bakes = true
        hold_bakes()

    self.track_changes

    dont_join = was_skipping_join
    if not self.model.bot_collisions:
      var layer = 0
      layer.set_bits(2)
      self.collision_layer = layer

    if self.model.cull_down_faces:
      self.set_cull_down_faces(true)

    # Greedy meshing is always on (identical render, far fewer vertices). The
    # engine keeps the toggle in case we ever want to expose it again, but it
    # isn't a script- or model-level option.
    self.set_greedy_meshing(true)

    self.model.sight_ray = self.get_node("SightRay") as RayCast
    self.prepare_materials()
    if self.model.current_frame >= 0:
      self.render_frame(self.model.current_frame)

proc init*(_: type BuildNode): BuildNode =
  if not ?build_scene:
    build_scene = load("res://components/BuildNode.tscn") as PackedScene
    shader = load("res://shaders/terrain_voxel.shader") as Shader
    hidden_shader = load("res://shaders/terrain_voxel_hidden.shader") as Shader
    rgb_shader = load("res://shaders/terrain_voxel_rgb.shader") as Shader
    hidden_rgb_shader =
      load("res://shaders/terrain_voxel_hidden_rgb.shader") as Shader
  result = build_scene.instance() as BuildNode
