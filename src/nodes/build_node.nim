import std/[tables, bitops, times, options, sets, hashes, os]
import pkg/godot except print, Color
import
  godotapi/[
    node, spatial, voxel_terrain, voxel_mesher_blocky, voxel_mesher,
    voxel_tool, voxel_library, voxel_buffer, voxel_server, shader_material,
    resource_loader, packed_scene, ray_cast, mesh,
  ]
import core, models/[things, builds, colors, voxels], gdutils
import ./queries, ./voxel_library_registry, ./build_node_frames

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

let prefill_disabled = get_env("ENU_NO_PREFILL") == "1"
  ## A/B switch: disable the enu_chunk_bytes prefill so paged-in blocks take
  ## the old paint-after-load path (perf comparison).
let perf_log = get_env("ENU_PERF_LOG") != ""

var build_scene {.threadvar.}: PackedScene
var shader {.threadvar.}: Shader
var hidden_shader {.threadvar.}: Shader
var rgb_shader {.threadvar.}: Shader
var hidden_rgb_shader {.threadvar.}: Shader

proc to_pool_byte_array(s: string): PoolByteArray =
  result = new_pool_byte_array()
  result.set_len(s.len)
  for i in 0 ..< s.len:
    result[i] = s[i].byte

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
    next_stats_log: MonoTime
    prefill_hits, prefill_misses: int
    loaded_chunks: HashSet[Vector3]
    prefilled_chunks: Table[Vector3, int]
      ## Chunks the request-time hook (enu_chunk_bytes) answered with real bytes,
      ## so the streaming thread prefilled the engine block with them, mapped to
      ## the served content's voxel count. Consumed by on_block_loaded to skip
      ## the now-redundant snapshot + delta paints while still crediting
      ## rendered_voxel_count. See docs/notes/voxel-stream-loading.md.
    tracked_delta_seqs: Table[Vector3, EID]
    renderer: VoxelRenderer
    paging_logged: bool
    data_logged: bool
    holding_bakes: bool
    frames: FramePlayer
      ## Frame-animation playback (save/play flipbooks). Owns the mesh cache
      ## and per-chunk display bookkeeping; see build_node_frames.nim. Created
      ## in setup once the renderer/resolver exist.
    next_warm_log: MonoTime

  proc init*() =
    self.bind_signals self, "block_loaded", "block_unloaded",
      "frame_mesh_baked", "mesh_block_created"
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
      if added:
        if chunk_id in self.loaded_chunks:
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
        else:
          # Delta appended while the chunk is still paging in: the prefilled
          # buffer was composed at request time and predates it, so drop the hint
          # and let on_block_loaded repaint the fresh state instead of skipping.
          self.prefilled_chunks.del chunk_id

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

  method on_mesh_block_created(chunk_id: Vector3) =
    ## A mesh block was (re)created by viewer pairing. Any display state the
    ## frame player recorded for it belonged to the previous block instance —
    ## forget it, so the next flip re-queues and re-installs. Without this,
    ## chunks re-entering pairing range keep a stale "shown" entry and render
    ## whatever the pipeline meshed from data until their LOD target changes.
    if ?self.frames:
      self.frames.forget_display(chunk_id)

  method on_frame_mesh_baked(chunk_id: Vector3, tag: int, mesh: Mesh) =
    ## Godot signal callback (bind_signals "frame_mesh_baked") — hand the bake
    ## to the frame player.
    if ?self.frames:
      self.frames.on_mesh_baked(chunk_id, tag, mesh)

  proc publish_palette_slots() =
    ## Push the build's static-palette-index -> engine voxel slot mapping to the
    ## terrain so the streaming thread can resolve paged-in chunks off-main. The
    ## palette (shared with the unit) lists every static color the build renders,
    ## in static-index order; named colors resolve as identity in the engine.
    if not ?self.model.shared:
      return
    let slots = new_pool_int_array()
    for color in self.model.shared.palette:
      slots.add slot_for(color).cint
    self.set_enu_palette_slots(slots)

  proc enu_chunk_bytes*(block_position: Vector3): PoolByteArray {.gdExport.} =
    ## Request-time hook (main thread, Ed-safe): hand the streaming pool this
    ## block's packed bytes so it's prefilled with real data and meshes once. An
    ## empty result means "not resident" — the engine falls back to an empty
    ## block and today's paint-after-load path carries it.
    ## ENU_NO_PREFILL=1 disables the hook for prefill-vs-paint A/B measurement.
    result = new_pool_byte_array()
    if not ?self.model or prefill_disabled:
      return
    let bytes = self.model.voxels.prefill_bytes(block_position)
    if bytes.len > 0:
      self.prefilled_chunks[block_position] = PackedChunk(data: bytes).voxel_count
      result = to_pool_byte_array(bytes)

  method on_block_loaded(chunk_id: Vector3) =
    let start = get_mono_time()
    if ?self.model:
      self.loaded_chunks.incl(chunk_id)
      # Consume the request-time hint: was this block prefilled with its data?
      var prefill_credit = 0
      let prefilled = self.prefilled_chunks.pop(chunk_id, prefill_credit)
      if prefilled:
        inc self.prefill_hits
        # The engine expanded the served bytes into this block; the paints
        # below are skipped for prefilled blocks, so credit their voxels here
        # or rendered_voxel_count never converges on the model count.
        self.model.rendered_voxel_count =
          self.model.rendered_voxel_count + prefill_credit
      else:
        inc self.prefill_misses

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
        elif prefilled:
          # Prefilled: the streaming thread already expanded this content into the
          # engine block, which meshed once. Skip the redundant paint — this is the
          # flash/double-mesh the whole change removes. (Counted above via
          # prefill_credit, not here.)
          discard
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
              elif not prefilled and ?self.renderer.voxel_tool:
                # prefilled blocks already carry these deltas (prefill_bytes
                # composed them in) — repainting would force a second mesh.
                painted = painted + render_delta_direct(
                  self.renderer.voxel_tool, chunk_id, delta, self.resolver
                )
            if painted > 0:
              self.model.rendered_voxel_count =
                self.model.rendered_voxel_count + painted

          self.watch_delta_seq(chunk_id, delta_seq)
      flush_registry()
      if displaying_frame:
        # give the fresh chunk its frame content on the next drain
        self.frames.show_chunk(chunk_id, self.model.current_frame)
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
      self.frames.drop_chunk(chunk_id)

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
        else:
          # Snapshot changed while the chunk is still loading: the prefilled
          # buffer was captured from the previous bytes, so drop the hint and let
          # on_block_loaded paint the fresh snapshot instead of skipping it.
          self.prefilled_chunks.del change.item.key
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
          else:
            # Deltas changed before the chunk finished loading: the prefilled
            # buffer predates them, so drop the hint and let on_block_loaded
            # repaint the fresh state rather than skipping it.
            self.prefilled_chunks.del chunk_id
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
        self.frames.reset()
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
        self.frames.render(change.item)

    self.model.frames.watch:
      if added or removed:
        self.frames.on_frames_changed()

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

      # Opt-in perf sampling (ENU_PERF_LOG): per-terrain cumulative counters.
      # `meshed` counts pipeline meshes actually applied — the number prefill
      # is meant to halve (born-with-data = 1 mesh vs empty + paint + remesh).
      if perf_log and get_mono_time() > self.next_stats_log:
        self.next_stats_log = get_mono_time() + init_duration(seconds = 2)
        let stats = self.get_statistics()
        info "TERRAIN", unit = self.model.id,
          meshed = parse_int($stats["updated_blocks"]),
          dropped_meshes = parse_int($stats["dropped_block_meshs"]),
          prefill_hits = self.prefill_hits,
          prefill_misses = self.prefill_misses

      # Frame playback: the server is the single advancing authority; the
      # synced current_frame drives rendering on every side. Each side runs its
      # own display/bake bookkeeping and harvests its miss set as bakes land.
      self.frames.tick()
      self.frames.advance_playback()

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
    # Memoized: palette indices never re-map (the palette is append-only),
    # and slot_for hashes a Color per call — far too hot for per-voxel
    # resolution in the frame drain (profiled at ~13% of main during paging).
    var slot_memo = init_table[int, int64]()
    self.resolver = proc(color_index: int): int64 =
      slot_memo.with_value(color_index, memoized):
        return memoized[]
      result = slot_for(resolve_color(model.shared, color_index))
      slot_memo[color_index] = result

    # Pre-register the build's whole palette (it syncs with the unit and
    # lists every static color the build will ever render), so a block
    # loading into view later never mints — and bakes — a new library entry.
    if ?self.model.shared:
      for color in self.model.shared.palette:
        discard slot_for(color)
      # Publish the resolved palette to the engine before any block streams in,
      # so the streaming thread can expand paged-in chunks. Republish on growth.
      self.publish_palette_slots()
      self.model.shared.palette.watch:
        if added:
          discard slot_for(change.item)
          self.publish_palette_slots()
      flush_registry() # no-op while an ephemeral stream holds bakes

    # Create renderer for ASAP mode buffer operations
    self.renderer = VoxelRenderer.init(self.get_voxel_tool(), self.resolver)

    # Frame playback reaches the terrain through the VoxelTerrain base and reads
    # the node's own loaded_chunks set (by pointer, same lifetime).
    self.frames = FramePlayer.init(
      terrain = self,
      model = self.model,
      renderer = self.renderer,
      resolver = self.resolver,
      loaded_chunks = addr self.loaded_chunks,
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
      self.frames.render(self.model.current_frame)

proc init*(_: type BuildNode): BuildNode =
  if not ?build_scene:
    build_scene = load("res://components/BuildNode.tscn") as PackedScene
    shader = load("res://shaders/terrain_voxel.shader") as Shader
    hidden_shader = load("res://shaders/terrain_voxel_hidden.shader") as Shader
    rgb_shader = load("res://shaders/terrain_voxel_rgb.shader") as Shader
    hidden_rgb_shader =
      load("res://shaders/terrain_voxel_hidden_rgb.shader") as Shader
  result = build_scene.instance() as BuildNode
