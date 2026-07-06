import std/[tables, bitops, times, options, sets, hashes, algorithm]
import pkg/godot except print, Color
import
  godotapi/[
    node, spatial, voxel_terrain, voxel_mesher_blocky, voxel_mesher,
    voxel_tool, voxel_library, voxel_buffer, voxel_server, shader_material,
    resource_loader, packed_scene, ray_cast, mesh_instance, mesh,
  ]
import core, models/[units, builds, colors, voxels], gdutils
import ./queries, ./voxel_library_registry

const
  highlight_glow = 1.0
  default_glow = 0.0
  error_flash_time = 0.5.seconds
  rgb_material_index = 6
    ## material/6: the shared vertex-color material static RGB voxels render
    ## with (materials 0..5 stay the uniform-tinted named colors).

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
    # Frame display (M2): saved frames render as cached meshes on plain
    # MeshInstance children — no voxel writes, no remeshing per flip. The
    # live block meshes hide via set_render_blocks_visible meanwhile; the
    # live data (and so collisions and queries) is never touched.
    frame_mesh_cache: Table[Hash, Mesh]
    frame_instances: Table[Vector3, MeshInstance]
    frames_showing: bool
    playback_logged: bool
    next_warm_log: MonoTime
    # paste-and-capture state: a cache miss pastes the frame's chunk into
    # the terrain like any other edit; the engine meshes it on its threads
    # and on_mesh_block_updated captures the mesh into frame_mesh_cache.
    frame_pending_capture:
      Table[Vector3, tuple[key: Hash, at: MonoTime, min_version: int]]
    frame_applied: Table[Vector3, Hash] # frame content currently in terrain
    frame_dirty: HashSet[Vector3] # terrain data differs from live state
    frame_mesh_lru: Table[Hash, int] # last-touched tick per cached mesh
    frame_lru_tick: int
    frame_pastes: int # since the last stats log
    frame_pastes_this_tick: int
    frame_signals: int
    frame_captures: int
    frame_new_keys: int
    next_frame_stats: MonoTime

  proc init*() =
    self.bind_signals self, "block_loaded", "block_unloaded",
      "mesh_block_updated"
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

  proc snapshot_key(snapshot: SnapshotData): Hash =
    hash(snapshot.data)

  proc frame_instance(chunk_id: Vector3): MeshInstance =
    if chunk_id in self.frame_instances:
      result = self.frame_instances[chunk_id]
    else:
      result = gdnew[MeshInstance]()
      result.translation = chunk_id * ChunkDim.float
      self.add_child(result)
      self.frame_instances[chunk_id] = result

  proc paste_frame_chunk(chunk_id: Vector3, snapshot: SnapshotData, key: Hash) =
    render_snapshot_replace(
      self.renderer.voxel_tool, chunk_id, snapshot, self.resolver
    )
    self.frame_dirty.incl chunk_id
    self.frame_applied[chunk_id] = key
    # Sample the block's request version at paste time: only a mesh built
    # by a LATER request is guaranteed to include this paste. Earlier
    # requests may still be in flight (neighbor border-remeshes constantly
    # re-mesh this block) and their meshes hold the pre-paste content —
    # capturing one of those under this key desynchronizes the chunk
    # permanently.
    self.frame_pending_capture[chunk_id] = (
      key, get_mono_time(), self.get_block_mesh_request_version(chunk_id).int
    )
    inc self.frame_pastes
    inc self.frame_pastes_this_tick

  proc show_frame(index: int) =
    ## Display frame `index`. Chunks with a cached mesh swap it in directly;
    ## misses paste the frame's chunk into the terrain like any other edit —
    ## the engine meshes it on its own threads and on_mesh_block_updated
    ## captures the result. Nothing is precalculated: each (chunk, content)
    ## pair meshes at most once, on demand, at native meshing speed.
    ##
    ## Until every chunk of a frame has a cached mesh the terrain itself
    ## displays the pasted frame (live meshes stay visible); once complete,
    ## the display swaps to instances and the live meshes hide. After the
    ## swap a miss keeps its previous frame's mesh until the capture lands.
    let frames = self.model.frames
    if index < 0 or index >= frames.len or not ?self.renderer.voxel_tool:
      return
    let frame = frames[index]
    flush_registry() # palette entries minted since the last flush
    if self.frame_pending_capture.len > 0:
      # a cancelled or dropped mesh task never signals; expire its slot so
      # backpressure can't jam (the chunk re-pastes on a later flip)
      let cutoff = get_mono_time() - init_duration(seconds = 5)
      var expired: seq[Vector3]
      for chunk_id, entry in self.frame_pending_capture:
        if entry.at < cutoff:
          expired.add chunk_id
      for chunk_id in expired:
        self.frame_pending_capture.del chunk_id
        self.frame_applied.del chunk_id # force a re-paste
    var missing = 0
    for chunk_id in self.loaded_chunks:
      if chunk_id notin frame.chunks:
        if chunk_id in self.frame_instances:
          self.frame_instances[chunk_id].visible = false
        if not self.frames_showing and
            self.frame_applied.get_or_default(chunk_id, Hash(0)) != Hash(0):
          erase_chunk_direct(self.renderer.voxel_tool, chunk_id)
          self.frame_applied.del chunk_id
        continue
      let snapshot = frame.chunks[chunk_id]
      let key = self.snapshot_key(snapshot)
      let cached = key in self.frame_mesh_cache
      if not cached:
        inc missing
      # Backpressure, two-dimensional: bounded in-flight captures (the
      # engine's apply queue holds full surface arrays per entry — letting
      # it grow eats the PoolVector pool), and bounded pastes per process
      # tick (a paste burst stalls the main thread, which starves the
      # time-spread apply runner, which is the death spiral). Skipped
      # chunks keep their previous content and catch up on later flips.
      # Never repaste a chunk that's already awaiting capture: a new paste
      # bumps the block's mesh-request version, permanently outdating the
      # in-flight mesh — repasting every flip means nothing ever captures.
      # The chunk keeps showing its in-flight frame until the capture
      # lands, then rejoins the rotation.
      let can_paste =
        chunk_id notin self.frame_pending_capture and
        self.frame_pending_capture.len < 256 and
        self.frame_pastes_this_tick < 16
      if self.frames_showing:
        if cached:
          self.touch_cached(key)
          let inst = self.frame_instance(chunk_id)
          inst.mesh = self.frame_mesh_cache[key]
          inst.visible = ?inst.mesh
        elif can_paste and
            self.frame_applied.get_or_default(chunk_id, Hash(0)) != key:
          self.paste_frame_chunk(chunk_id, snapshot, key)
      elif not cached and can_paste and
          self.frame_applied.get_or_default(chunk_id, Hash(0)) != key:
        # Warming: paste budget goes to UNCACHED keys only. Refreshing
        # already-cached chunks onto the displayed frame looks nicer but
        # monopolizes the per-tick budget on the same first N chunks
        # forever (stable iteration order) — nothing else ever pastes and
        # the cache never converges. Chunks hold their last-pasted frame
        # (a patchwork during warm-up) until the swap.
        self.paste_frame_chunk(chunk_id, snapshot, key)
    flush_registry()
    if not self.frames_showing:
      if missing > 0:
        let now = get_mono_time()
        if now > self.next_warm_log:
          self.next_warm_log = now + init_duration(seconds = 5)
          info "frame warm-up",
            unit = self.model.id,
            frame = index,
            missing = missing,
            loaded = self.loaded_chunks.len
        return # the pasted live meshes are displaying this frame meanwhile
      self.frames_showing = true
      info "frames showing", unit = self.model.id, frame = index
      self.set_render_blocks_visible(false)
      for chunk_id in self.loaded_chunks:
        if chunk_id in frame.chunks:
          let key = self.snapshot_key(frame.chunks[chunk_id])
          if key in self.frame_mesh_cache:
            let inst = self.frame_instance(chunk_id)
            inst.mesh = self.frame_mesh_cache[key]
            inst.visible = ?inst.mesh

  proc hide_frames() =
    self.frame_pending_capture.clear()
    if self.frames_showing:
      self.frames_showing = false
      for _, inst in self.frame_instances:
        inst.visible = false
      self.set_render_blocks_visible(true)
    if self.frame_dirty.len > 0 and ?self.renderer.voxel_tool:
      # restore the live voxel state wherever frame content was pasted
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
    self.frame_applied.clear()

  method on_mesh_block_updated(chunk_id: Vector3, version: int) =
    if not ?self.model:
      return
    inc self.frame_signals
    if chunk_id notin self.frame_pending_capture:
      return
    let entry = self.frame_pending_capture[chunk_id]
    if version <= entry.min_version:
      # built by a request sent before our paste: pre-paste content. Our
      # paste forces a later request, so a valid capture is still coming.
      return
    inc self.frame_captures
    let key = entry.key
    self.frame_pending_capture.del chunk_id
    var mesh: Mesh
    if self.frames_showing:
      # blocks are hidden: steal the mesh outright so later block updates
      # can't mutate it (mesh updates reuse the block's ArrayMesh in place)
      mesh = self.get_block_mesh(chunk_id, true)
    else:
      # warming: the block's mesh is on screen — copy it instead
      let m = self.get_block_mesh(chunk_id, false)
      if ?m:
        mesh = m.duplicate.as(Mesh)
    if key notin self.frame_mesh_cache:
      inc self.frame_new_keys
    # nil is a valid entry: an all-hole chunk meshes to nothing, and caching
    # that stops it from repasting every flip
    self.store_cached(key, mesh)
    if self.frames_showing:
      # held frames never re-flip, so attach on capture when this chunk is
      # part of the displayed frame
      let current = self.model.current_frame
      if current >= 0 and current < self.model.frames.len:
        let frame = self.model.frames[current]
        if chunk_id in frame.chunks and
            self.snapshot_key(frame.chunks[chunk_id]) == key:
          let inst = self.frame_instance(chunk_id)
          inst.mesh = mesh
          inst.visible = ?mesh

  proc render_frame(index: int) =
    ## Display a saved frame (or the live state for index < 0). Frames render
    ## as baked, content-hash-cached meshes on MeshInstance children while
    ## the live render meshes hide via set_render_blocks_visible — voxel
    ## data, collisions and spatial queries always reflect the live state.
    ## The instances inherit the node's transform, so scaled builds animate
    ## correctly. Only SHOWING is gated on ASAP: hiding must always run —
    ## reset turns ASAP on before it clears current_frame, and skipping the
    ## hide there would leave every block invisible after the rerun.
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
        # as empty handles with the unit.
        self.model.voxels.packed_chunks.request(chunk_id)
        self.model.voxels.chunk_deltas.request(chunk_id)
        if not self.paging_logged:
          self.paging_logged = true
          # One line per build: paired with "voxel data arriving" below, a
          # build that requests but never receives is visible in the logs.
          info "voxel paging", unit = self.model.id

      if chunk_id in self.model.voxels.packed_chunks:
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
      if self.frames_showing or (
        self.model.current_frame >= 0 and
        self.model.current_frame < self.model.frames.len and
        ASAP_MODE notin self.model.global_flags
      ):
        # give the fresh chunk its frame content (cheap for the rest:
        # applied-tag checks make the loop a no-op elsewhere)
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
      if chunk_id in self.frame_instances:
        self.frame_instances[chunk_id].visible = false
      self.frame_pending_capture.del chunk_id
      self.frame_applied.del chunk_id

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
          info "voxel data arriving", unit = self.model.id
        if change.item.key in self.loaded_chunks:
          if ASAP_MODE in self.model.global_flags:
            self.renderer.buffer_snapshot(change.item.key, change.item.value)
          elif ?self.renderer.voxel_tool:
            render_snapshot_direct(
              self.renderer.voxel_tool, change.item.key, change.item.value
            )
      elif removed and not modified:
        # Paged out (chunk paging; a rewrite is REMOVED+MODIFIED and skipped) —
        # clear it from the terrain. The data still exists on the server;
        # moving back re-requests and re-renders.
        if change.item.key in self.loaded_chunks and ?self.renderer.voxel_tool:
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
        # frame content changed; keys are content hashes, so the mesh cache
        # stays valid — just re-evaluate what's displayed
        self.render_frame(self.model.current_frame)

    self.model.scale_value.watch:
      if added:
        # Scale lives in the model's transform.basis (set synchronously by
        # `scale=`); the node picks it up via transform_value below. Here we
        # only adjust the view distance for the new scale.
        self.max_view_distance =
          int(self.default_view_distance.float / change.item)

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
      # synced current_frame drives rendering on every side.
      self.frame_pastes_this_tick = 0

      if self.frames_showing or self.frame_pending_capture.len > 0:
        let now2 = get_mono_time()
        if now2 > self.next_frame_stats:
          self.next_frame_stats = now2 + init_duration(seconds = 15)
          info "frame stats",
            unit = self.model.id,
            cached = self.frame_mesh_cache.len,
            pending = self.frame_pending_capture.len,
            pastes = self.frame_pastes,
            signals = self.frame_signals,
            captures = self.frame_captures,
            new_keys = self.frame_new_keys
          self.frame_pastes = 0
          self.frame_signals = 0
          self.frame_captures = 0
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

      if SERVER in state.local_flags and self.model.frames_fps > 0 and
          self.model.frames.len > 1:
        let now = get_mono_time()
        if now >= self.next_frame_at:
          self.next_frame_at =
            now + init_duration(
              milliseconds = int(1000.0 / self.model.frames_fps)
            )
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
