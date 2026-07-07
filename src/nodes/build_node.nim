import std/[tables, bitops, times, options, sets, hashes, algorithm]
import pkg/godot except print, Color
import
  godotapi/[
    node, spatial, voxel_terrain, voxel_mesher_blocky, voxel_mesher,
    voxel_tool, voxel_library, voxel_buffer, voxel_server, shader_material,
    resource_loader, packed_scene, ray_cast, mesh,
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
    frame_missing: Table[Vector3, Hash] # misses awaiting harvest
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
    self.bind_signals self, "block_loaded", "block_unloaded"
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

  proc keys_for_frame(index: int): lent Table[Vector3, Hash] =
    if index notin self.frame_keys:
      self.frame_keys[index] = frame_chunk_keys(self.model.frames[index])
    self.frame_keys[index]

  proc write_frame_chunk(
      chunk_id: Vector3, snapshot: SnapshotData, remesh: bool
  ) =
    fill_chunk_type_bytes(self.frame_bytes, snapshot, self.resolver)
    discard self.set_block_voxel_data(chunk_id, self.frame_bytes, remesh)
    self.frame_dirty.incl chunk_id

  proc show_frame(index: int) =
    ## Display frame `index` by writing its content into the terrain. Chunks
    ## whose content key has a cached mesh get the data silently (no remesh)
    ## plus the mesh directly; misses write normally and the engine meshes
    ## them like any other edit. Misses are recorded in `frame_missing` and
    ## harvested into the cache once the mesh pipeline drains (see process);
    ## playback holds the frame until then, so nothing is ever captured that
    ## wasn't built from this frame's data.
    let frames = self.model.frames
    if index < 0 or index >= frames.len or not ?self.renderer.voxel_tool:
      return
    let frame = frames[index]
    flush_registry() # palette entries minted since the last flush
    const EMPTY_CHUNK_KEY = Hash(0)
    for chunk_id in self.loaded_chunks:
      let target = self.keys_for_frame(index).get_or_default(
        chunk_id, EMPTY_CHUNK_KEY
      )
      if chunk_id in self.frame_display and
          self.frame_display[chunk_id] == target:
        continue
      self.frame_missing.del chunk_id
      if chunk_id notin frame.chunks:
        self.write_frame_chunk(chunk_id, SnapshotData(), remesh = false)
        self.set_block_mesh(chunk_id, nil)
      elif target in self.frame_mesh_cache:
        self.touch_cached(target)
        self.write_frame_chunk(chunk_id, frame.chunks[chunk_id], remesh = false)
        self.set_block_mesh(chunk_id, self.frame_mesh_cache[target])
      else:
        self.write_frame_chunk(chunk_id, frame.chunks[chunk_id], remesh = true)
        self.frame_missing[chunk_id] = target
      self.frame_display[chunk_id] = target
    flush_registry()

  proc harvest_frame_meshes() =
    ## Collect meshes for the displayed frame's misses. Only runs when the
    ## terrain's whole mesh pipeline is drained: at that point every missed
    ## block's mesh was built from the data currently in the terrain — the
    ## displayed frame — so key/mesh attribution is exact by construction.
    ## (A shared mesh is never rebuilt in place: the engine only reuses a
    ## block's ArrayMesh when nothing else holds a reference to it.)
    if int(self.get_pending_block_updates()) > 0 or self.renderer.dirty:
      let now = get_mono_time()
      if now > self.next_warm_log:
        self.next_warm_log = now + init_duration(seconds = 5)
        info "frame warm-up",
          unit = self.model.id,
          frame = self.model.current_frame,
          missing = self.frame_missing.len,
          cached = self.frame_mesh_cache.len
      return
    for chunk_id, key in self.frame_missing:
      # nil is a valid mesh: an all-hole chunk meshes to nothing, and
      # caching that stops it from re-missing every loop
      if key notin self.frame_mesh_cache:
        inc self.frame_new_keys
      self.store_cached(key, self.get_block_mesh(chunk_id, false))
      inc self.frame_harvests
    self.frame_missing.clear()

  proc hide_frames() =
    self.frame_missing.clear()
    self.frame_display.clear()
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
        # as empty handles with the unit.
        self.model.voxels.packed_chunks.request(chunk_id)
        self.model.voxels.chunk_deltas.request(chunk_id)
        if not self.paging_logged:
          self.paging_logged = true
          # One line per build: paired with "voxel data arriving" below, a
          # build that requests but never receives is visible in the logs.
          info "voxel paging", unit = self.model.id

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
          info "voxel data arriving", unit = self.model.id
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
        self.harvest_frame_meshes()

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
      if SERVER in state.local_flags and self.model.frames_fps > 0 and
          self.model.frames.len > 1 and self.frame_missing.len == 0:
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

    self.frame_bytes = new_pool_byte_array()
    self.frame_bytes.set_len(CHUNK_VOLUME * 2)

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
