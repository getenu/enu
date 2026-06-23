import std/[tables, bitops, times, options, sets]
import pkg/godot except print, Color
import
  godotapi/[
    node, voxel_terrain, voxel_mesher_blocky, voxel_tool, voxel_library,
    voxel_buffer, voxel_server, shader_material, resource_loader, packed_scene,
    ray_cast,
  ]
import core, models/[units, builds, colors, voxels], gdutils
import ./queries

const
  highlight_glow = 1.0
  default_glow = 0.0
  error_flash_time = 0.5.seconds

var build_scene {.threadvar.}: PackedScene
var shader {.threadvar.}: Shader
var hidden_shader {.threadvar.}: Shader

gdobj BuildNode of VoxelTerrain:
  var
    model*: Build
    transform_zid: EID
    default_view_distance: int
    toggle_error_highlight_at = MonoTime.high
    error_highlight_on: bool
    loaded_chunks: HashSet[Vector3]
    tracked_delta_seqs: Table[Vector3, EID]
    renderer: VoxelRenderer
    paging_logged: bool
    data_logged: bool

  proc init*() =
    self.bind_signals self, "block_loaded", "block_unloaded"
    self.default_view_distance = self.max_view_distance.int

  proc prepare_materials() =
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

  proc watch_delta_seq(chunk_id: Vector3, delta_seq: EdSeq[DeltaUpdate]) =
    if chunk_id in self.tracked_delta_seqs:
      return

    let zid = delta_seq.watch:
      if added and chunk_id in self.loaded_chunks:
        var painted = 0
        if ASAP_MODE in self.model.global_flags:
          painted = self.renderer.buffer_delta(chunk_id, change.item)
        elif ?self.renderer.voxel_tool:
          painted =
            render_delta_direct(self.renderer.voxel_tool, chunk_id, change.item)
        self.model.rendered_voxel_count =
          self.model.rendered_voxel_count + painted

    self.tracked_delta_seqs[chunk_id] = zid

  method on_block_loaded(chunk_id: Vector3) =
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
            self.renderer.voxel_tool, chunk_id, snapshot
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
                self.renderer.voxel_tool, chunk_id, delta
              )
          if painted > 0:
            self.model.rendered_voxel_count =
              self.model.rendered_voxel_count + painted

          self.watch_delta_seq(chunk_id, delta_seq)

  method on_block_unloaded(chunk_id: Vector3) =
    if ?self.model:
      self.loaded_chunks.excl(chunk_id)
      if SERVER notin state.local_flags:
        # Out of view: page out. Evicts locally (the excl above keeps the
        # REMOVED watch from erasing an already-dropped block) and retracts
        # our per-key interest upstream — never touches the authority's data.
        self.model.voxels.packed_chunks.release(chunk_id)
        self.model.voxels.chunk_deltas.release(chunk_id)

  proc set_glow(glow: float) =
    let library = self.mesher.as(VoxelMesherBlocky).library
    for i in 0 ..< library.voxel_count.int:
      let m = self.get_material(i).as(ShaderMaterial)
      if ?m:
        m.set_shader_param("emission_energy", glow.to_variant)

  proc set_highlight() =
    let library = self.mesher.as(VoxelMesherBlocky).library
    for i in 0 ..< library.voxel_count.int:
      let m = self.get_material(i).as(ShaderMaterial)
      if ?m:
        if self.error_highlight_on:
          m.set_shader_param("emission", ACTION_COLORS[RED].to_variant)
        else:
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

      for material in self.model.shared.materials:
        material.shader = shader
    elif VISIBLE notin self.model.global_flags and GOD in state.local_flags:
      self.visible = true

      for material in self.model.shared.materials:
        material.shader = hidden_shader
    else:
      self.visible = false

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
      for chunk_id, snapshot in self.model.voxels.packed_chunks:
        if chunk_id in self.loaded_chunks:
          render_snapshot_direct(self.renderer.voxel_tool, chunk_id, snapshot)

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
                render_delta_direct(self.renderer.voxel_tool, chunk_id, delta)
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
      for chunk_id, delta_seq in self.model.voxels.chunk_deltas:
        if ?delta_seq:
          if chunk_id in self.loaded_chunks:
            for delta in delta_seq:
              render_delta_direct(self.renderer.voxel_tool, chunk_id, delta)
          self.watch_delta_seq(chunk_id, delta_seq)

    self.model.global_flags.watch:
      if (
        change.item == VISIBLE and
        SCRIPT_INITIALIZING notin self.model.global_flags
      ) or SCRIPT_INITIALIZING.removed:
        self.set_visibility
      elif RESETTING.added:
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
        elif removed:
          self.renderer.end_asap()

    self.model.local_flags.watch:
      if change.item == HIGHLIGHT:
        self.set_highlight

    state.local_flags.watch:
      if change.item == GOD:
        self.set_visibility

    self.model.scale_value.watch:
      if added:
        # Scale lives in the model's transform.basis (set synchronously by
        # `scale=`); the node picks it up via transform_value below. Here we
        # only adjust the view distance for the new scale.
        self.max_view_distance =
          int(self.default_view_distance.float / change.item)

    self.transform_zid = self.model.transform_value.watch:
      if added:
        self.transform = change.item

    self.model.sight_query_value.watch:
      if added:
        var query = change.item
        let collision_layer = self.collision_layer
        self.collision_layer = 0
        query.run(self.model)
        self.collision_layer = collision_layer
        self.model.sight_query = query

  method process(delta: float) =
    if ?self.model:
      if self.model.code.owner == state.worker_ctx_name:
        self.model.transform_value.pause self.transform_zid:
          self.model.transform = self.transform

      if get_mono_time() > self.toggle_error_highlight_at:
        self.error_highlight_on = not self.error_highlight_on
        self.toggle_error_highlight_at = get_mono_time() + error_flash_time
        self.set_highlight()

      let is_local = self.model.code.owner == state.worker_ctx_name
      self.renderer.tick(is_local)

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

    # Create renderer for ASAP mode buffer operations
    self.renderer = VoxelRenderer.init(self.get_voxel_tool())

    # Builds default to ASAP, so the flag is usually set before this node
    # exists — the ASAP_MODE.added watch never fires for it. Adopt the
    # current state here; the watch handles later transitions.
    if ASAP_MODE in self.model.global_flags:
      self.renderer.begin_asap()

    self.track_changes

    dont_join = was_skipping_join
    if not self.model.bot_collisions:
      var layer = 0
      layer.set_bits(2)
      self.collision_layer = layer

    self.model.sight_ray = self.get_node("SightRay") as RayCast
    self.prepare_materials()

proc init*(_: type BuildNode): BuildNode =
  if not ?build_scene:
    build_scene = load("res://components/BuildNode.tscn") as PackedScene
    shader = load("res://shaders/terrain_voxel.shader") as Shader
    hidden_shader = load("res://shaders/terrain_voxel_hidden.shader") as Shader
  result = build_scene.instance() as BuildNode
