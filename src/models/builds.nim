import
  std/[
    tables, sets, options, sequtils, math, wrapnils, monotimes, sugar, deques,
    macros, base64, strformat,
  ]
import godotapi/spatial
import core, models/[states, bots, colors, units, packed_chunks, voxel_store]

# Re-export constants from voxel_store
export ChunkSize, MAX_BLOCK_COUNT, MAX_DELTA_UPDATES

include "build_code_template.nim.nimf"

const default_color = action_colors[Blue]

proc packed_chunks_enabled*(): bool =
  ## Check if packed chunks are enabled. Handles nil state.
  result = state.isNil or not state.disable_packed_chunks

var
  current_build* {.threadvar.}: Build
  previous_build* {.threadvar.}: Build
  last_placement_time* {.threadvar.}: MonoTime
  dont_join*: bool
  skip_point = vec3()
  last_point: Vector3
  draw_normal = vec3()

proc draw*(self: Build, position: Vector3, voxel: VoxelInfo) {.gcsafe.}
proc flush_packed_chunks*(self: Build) {.gcsafe.}
proc init_voxels_if_needed*(self: Build) {.gcsafe.}
proc verify_packed_chunks*(self: Build) {.gcsafe.}

method code_template*(self: Build, imports: string): string =
  result = build_code_template(
    read_file(self.script_ctx.script).encode(safe = true),
    self.script_ctx.script,
    imports,
  )

proc buffer(position: Vector3): Vector3 =
  (position / ChunkSize).floor

proc contains*(self: Build, position: Vector3): bool =
  let buf = position.buffer
  # Check both committed chunks and batched voxels
  if buf in self.voxels.chunks and position in self.voxels.chunks[buf]:
    return true
  if self.voxels.batching and buf in self.voxels.batched_voxels and
      position in self.voxels.batched_voxels[buf]:
    return true

proc voxel_info*(self: Build, position: Vector3): VoxelInfo =
  let buf = position.buffer
  # Check batched voxels first (they may override committed chunks)
  if self.voxels.batching and buf in self.voxels.batched_voxels and
      position in self.voxels.batched_voxels[buf]:
    return self.voxels.batched_voxels[buf][position]
  self.voxels.chunks[buf][position]

proc find_voxel*(self: Build, position: Vector3): Option[VoxelInfo] =
  let buf = position.buffer
  # Check batched voxels first
  if self.voxels.batching and buf in self.voxels.batched_voxels and
      position in self.voxels.batched_voxels[buf]:
    return some(self.voxels.batched_voxels[buf][position])
  if buf in self.voxels.chunks and position in self.voxels.chunks[buf]:
    return some(self.voxels.chunks[buf][position])
  none(VoxelInfo)

proc find_first*(units: ZenSeq[Unit], positions: open_array[Vector3]): Build =
  for unit in units:
    if unit of Build:
      let unit = Build(unit)
      let offset = vec3().global_from(unit)
      for position in positions:
        var loc = position - offset
        if loc in unit:
          var info = unit.voxels.chunks[loc.buffer][loc]
          if info.kind != Hole and info.color != action_colors[Eraser]:
            return unit
      let first = unit.units.find_first(positions)
      if ?first:
        return first

proc add_build(self, source: Build) =
  # Check if merging would exceed limit
  if self.voxels.block_count + source.voxels.block_count > MAX_BLOCK_COUNT:
    raise (ref ResourceLimitError)(
      msg: &"{self.id}: Block limit exceeded ({MAX_BLOCK_COUNT} blocks maximum)"
    )

  dont_join = true
  for chunk_id, chunk in source.voxels.chunks:
    for position, info in chunk:
      var position = position.global_from(source)
      position = position.local_to(self)
      self.draw(position, info)

  if source.parent.is_nil:
    state.units -= source
  else:
    source.parent.units -= source
  dont_join = false

proc maybe_join_previous_build(
    self: Build, position: Vector3, voxel: VoxelInfo
) =
  if self != current_build:
    previous_build = current_build
    current_build = self
    last_placement_time = get_mono_time()

  if ?previous_build and previous_build != self:
    var partner = previous_build
    let root = previous_build.find_root
    if root of Build:
      partner = Build(root)

    if partner != self:
      for position in position.global_from(self).surrounding:
        if position.local_to(partner) in partner:
          var source, dest: Build
          if partner.code.nim.strip == "":
            source = partner
            dest = self
          elif self.code.nim.strip == "":
            source = self
            dest = partner

          if ?source and ?dest:
            dest.add_build(source)
            current_build = dest
            return

proc expand_bounds_to_chunk(self: Build, chunk_id: Vector3) =
  let range = chunk_id * ChunkSize
  let min = range - ChunkSize - vec3(1, 1, 1)
  let max = range + ChunkSize
  if max notin self.bounds:
    self.bounds = self.bounds.expand(max)
  if min notin self.bounds:
    self.bounds = self.bounds.expand(min)

proc reset_bounds*(self: Build) =
  self.bounds = init_aabb(vec3(), vec3(-1, -1, -1))

  for chunk_id, chunk in self.voxels.chunks:
    self.expand_bounds_to_chunk(chunk_id)

proc verify_block_count(self: Build) =
  var actual_count = 0
  for chunk_id, chunk in self.voxels.chunks:
    for position, info in chunk:
      if info.kind != Hole:
        inc actual_count

  if actual_count != self.voxels.block_count:
    raise_assert &"Block count mismatch for {self.id}: counter={self.voxels.block_count}, actual={actual_count}"

proc add_voxel(self: Build, position: Vector3, voxel: VoxelInfo) =
  let buffer = position.buffer

  if buffer notin self.voxels.chunks:
    self.voxels.chunks[buffer] = self.voxels.create_chunk()
    self.expand_bounds_to_chunk(buffer)

  if packed_chunks_enabled():
    self.voxels.dirty_chunks.incl(buffer)

  # Check if voxel exists in either current chunks or batched voxels
  let exists_in_chunks = position in self.voxels.chunks[buffer]
  let exists_in_batched = self.voxels.batching and
                          buffer in self.voxels.batched_voxels and
                          position in self.voxels.batched_voxels[buffer]

  if self.voxels.batching:
    if position notin self.voxels.chunks[buffer] or
        self.voxels.chunks[buffer][position] != voxel:
      if buffer notin self.voxels.batched_voxels:
        self.voxels.batched_voxels[buffer] = init_table[Vector3, VoxelInfo]()

      # Check limit before adding new voxel
      if not exists_in_chunks and not exists_in_batched:
        if self.voxels.block_count >= MAX_BLOCK_COUNT:
          raise (ref ResourceLimitError)(
            msg: &"{self.id}: Block limit exceeded ({MAX_BLOCK_COUNT} blocks maximum)"
          )
        inc self.voxels.block_count
        when defined(debug):
          if self.voxels.block_count mod CHECK_INTERVAL == 0:
            self.verify_block_count()

      self.voxels.batched_voxels[buffer][position] = voxel
  else:
    if not exists_in_chunks:
      if self.voxels.block_count >= MAX_BLOCK_COUNT:
        raise (ref ResourceLimitError)(
          msg: &"{self.id}: Block limit exceeded ({MAX_BLOCK_COUNT} blocks maximum)"
        )
      inc self.voxels.block_count
      when defined(debug):
        if self.voxels.block_count mod CHECK_INTERVAL == 0:
          self.verify_block_count()
    self.voxels.chunks[buffer][position] = voxel

proc del_voxel(self: Build, position: Vector3) =
  let buffer = position.buffer
  if buffer in self.voxels.chunks and position in self.voxels.chunks[buffer]:
    dec self.voxels.block_count
    if packed_chunks_enabled():
      self.voxels.dirty_chunks.incl(buffer)
  self.voxels.chunks[buffer].del position

proc restore_edits*(self: Build) =
  if self.id in self.shared.edits:
    for loc, info in self.shared.edits[self.id]:
      assert info.kind in {Manual, Hole}
      if info.kind != Hole:
        self.add_voxel(loc, info)
      else:
        let buffer = loc.buffer
        if buffer in self.voxels.chunks and loc in self.voxels.chunks[buffer]:
          var info = info
          info.color = self.voxels.chunks[buffer][loc].color
          var locations = self.shared.edits[self.id]
          locations[loc] = info
          self.shared.edits[self.id] = locations
          self.voxels.chunks[buffer].del loc

proc draw*(self: Build, position: Vector3, voxel: VoxelInfo) {.gcsafe.} =
  if voxel.kind == Computed:
    if position in self.shared.edits[self.id]:
      var edit = self.shared.edits[self.id][position]
      if edit.kind == Hole:
        # We're using color as a flag to indicate that the hole is active
        edit.color = voxel.color
        var locations = self.shared.edits[self.id]
        locations[position] = edit
        self.shared.edits[self.id] = locations
        return
      elif edit.kind == Manual and edit.color == voxel.color:
        var locations = self.shared.edits[self.id]
        locations.del position
        self.shared.edits[self.id] = locations
    elif ?self.clone_of and
        position in self.clone_of.shared.edits[self.clone_of.id] and
        self.clone_of.shared.edits[self.clone_of.id][position].kind == Hole:
      return
    else:
      self.add_voxel(position, voxel)
  else:
    self.global_flags += Dirty
    # :( Crash fix hack. Why would shared be nil?
    if ?self.shared:
      if self.id notin self.shared.edits:
        self.shared.edits[self.id] = ~Table[Vector3, VoxelInfo]
      var voxel = voxel
      if voxel.kind == Hole and position in self:
        voxel.color = self.voxel_info(position).color
      var locations = self.shared.edits[self.id]
      locations[position] = voxel
      self.shared.edits[self.id] = locations
      if voxel.kind != Hole:
        self.add_voxel(position, voxel)
      else:
        self.del_voxel(position)

  if position == vec3(0, 0, 0) and voxel.kind != Computed:
    self.start_color = voxel.color

  if not dont_join and voxel.kind == Manual:
    self.maybe_join_previous_build(position, voxel)

proc drop_block(self: Build) =
  if self.drawing:
    var p = self.draw_transform.origin.snapped(vec3(1, 1, 1))
    self.draw(p, (Computed, self.color))

proc remove(self: Build) =
  if state.tool notin {CodeMode, PlaceBot}:
    state.skip_block_paint = true
    draw_normal = self.target_normal
    let point =
      self.target_point - self.target_normal -
      (self.target_normal.inverse_normalized * 0.5)

    skip_point = vec3()
    last_point = self.target_point
    self.draw(point, (Hole, action_colors[Eraser]))

    if self.units.len == 0 and
        not self.voxels.chunks.any_it(
          it.value.any_it(it.value.color != action_colors[Eraser])
        ):
      if self.parent.is_nil:
        state.units -= self
      else:
        self.parent.units -= self

proc fire(self: Build) =
  let global_point = self.target_point.global_from(self)
  if state.tool notin {Disabled, CodeMode, PlaceBot}:
    state.skip_block_paint = true
    draw_normal = self.target_normal
    let point = (self.target_point + (self.target_normal * 0.5)).floor
    skip_point = self.target_point + self.target_normal
    last_point = self.target_point
    self.draw(point, (Manual, state.selected_color))
  elif state.tool == PlaceBot and BlockTargetVisible in state.local_flags and
      state.bot_at(global_point).is_nil:
    let transform = Transform.init(origin = global_point)
    state.units += Bot.init(transform = transform)
  elif state.tool == CodeMode:
    let root = self.find_root
    state.open_unit = root

proc is_moving(self: Build, move_mode: int): bool =
  move_mode == 2

method batch_changes*(self: Build): bool =
  self.init_voxels_if_needed()
  if not self.voxels.batching:
    self.voxels.batching = true
    result = true

method apply_changes*(self: Build) =
  if self.voxels.batching:
    # Block counting now handled in add_voxel
    for buffer, chunk in self.voxels.batched_voxels:
      self.voxels.chunks[buffer] += chunk

    self.voxels.batched_voxels.clear
    self.voxels.batching = false

  # Encode dirty chunks for network sync
  if packed_chunks_enabled():
    if self.voxels.dirty_chunks.len > 0:
      self.flush_packed_chunks()

proc chunk_to_local(chunk_id: Vector3, pos: Vector3): int =
  ## Convert world position to linear index within chunk
  let local_x = int(pos.x - chunk_id.x * 16) mod 16
  let local_y = int(pos.y - chunk_id.y * 16) mod 16
  let local_z = int(pos.z - chunk_id.z * 16) mod 16
  linear_position(local_x, local_y, local_z)

proc get_or_create_delta_seq(self: Build, chunk_id: Vector3): ZenSeq[DeltaUpdate] =
  ## Get existing delta seq or create a new one for the chunk.
  if chunk_id in self.voxels.chunk_deltas:
    result = self.voxels.chunk_deltas[chunk_id]
  else:
    result = ~(seq[DeltaUpdate], {SyncLocal, SyncRemote})
    self.voxels.chunk_deltas[chunk_id] = result

proc flush_packed_chunks*(self: Build) =
  ## Encode dirty chunks using two-tier system:
  ## - packed_chunks: Full chunk snapshots (for late-connecting clients)
  ## - chunk_deltas: Per-chunk incremental changes (for connected clients)
  ##
  ## No-op when packed chunks are disabled.
  if not packed_chunks_enabled():
    return

  for chunk_id in self.voxels.dirty_chunks:
    # Build current voxel state and track positions with values
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    var current_voxels: Table[Vector3, PackedVoxel]

    if chunk_id in self.voxels.chunks:
      let chunk_value = self.voxels.chunks[chunk_id].value
      for pos, info in chunk_value:
        let linear = chunk_to_local(chunk_id, pos)
        let color_idx = info.color.action_index.ord
        let kind_ord = info.kind.ord
        let packed = pack_voxel(color_idx, kind_ord)
        voxels[linear] = packed
        current_voxels[pos] = packed

    # Get last snapshot state for this chunk
    let had_snapshot = chunk_id in self.voxels.last_snapshot
    let last_voxels = if had_snapshot: self.voxels.last_snapshot[chunk_id]
                      else: initTable[Vector3, PackedVoxel]()

    # Determine changes since last snapshot
    var changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]]

    # Added or modified voxels
    for pos, packed in current_voxels:
      if pos notin last_voxels or last_voxels[pos] != packed:
        changes.add (pos, packed)

    # Removed voxels (now holes)
    for pos in last_voxels.keys:
      if pos notin current_voxels:
        changes.add (pos, EMPTY_VOXEL)

    # Get delta count for this chunk
    let delta_count = if chunk_id in self.voxels.chunk_deltas:
                        self.voxels.chunk_deltas[chunk_id].len
                      else: 0

    # Force snapshot if this chunk has too many deltas
    let force_snapshot = delta_count >= MAX_DELTA_UPDATES

    # Decide: delta or snapshot
    # Use snapshot if: forced, no previous snapshot, or chunk is now empty
    let use_snapshot = force_snapshot or not had_snapshot or
                       current_voxels.len == 0

    if use_snapshot:
      # Full snapshot - clear deltas and update snapshot
      let packed = encode_chunk(voxels)
      if packed.is_empty:
        if chunk_id in self.voxels.packed_chunks:
          self.voxels.packed_chunks.del(chunk_id)
        if chunk_id in self.voxels.chunk_deltas:
          self.voxels.chunk_deltas.del(chunk_id)
        if chunk_id in self.voxels.last_snapshot:
          self.voxels.last_snapshot.del(chunk_id)
      else:
        self.voxels.packed_chunks[chunk_id] = packed
        if chunk_id in self.voxels.chunk_deltas:
          self.voxels.chunk_deltas[chunk_id].clear
        self.voxels.last_snapshot[chunk_id] = current_voxels
    elif changes.len > 0:
      # Delta update - only send changes
      let delta = encode_delta(changes)
      let delta_seq = self.get_or_create_delta_seq(chunk_id)
      delta_seq.add delta
      # Update last_snapshot to current state
      self.voxels.last_snapshot[chunk_id] = current_voxels

  self.voxels.dirty_chunks.clear

  # Verify packed data matches actual chunks (debug builds only)
  when defined(debug):
    self.verify_packed_chunks()

proc verify_packed_chunks*(self: Build) =
  ## Verify that packed_chunks + chunk_deltas can reconstruct actual chunks.
  ## Raises an exception with details if there's a mismatch.
  if not packed_chunks_enabled():
    return

  # Collect all chunk_ids from actual chunks, snapshots, and deltas
  var all_chunk_ids: HashSet[Vector3]
  for chunk_id in self.voxels.chunks.value.keys:
    all_chunk_ids.incl(chunk_id)
  for chunk_id in self.voxels.packed_chunks.value.keys:
    all_chunk_ids.incl(chunk_id)
  for chunk_id in self.voxels.chunk_deltas.value.keys:
    all_chunk_ids.incl(chunk_id)

  for chunk_id in all_chunk_ids:
    # Reconstruct chunk from snapshot + deltas
    var reconstructed: Table[Vector3, PackedVoxel]

    # Start with snapshot if exists
    if chunk_id in self.voxels.packed_chunks:
      let snapshot = self.voxels.packed_chunks[chunk_id]
      if snapshot.data.len > 0:
        let voxels = decode_chunk(snapshot)
        for linear in 0 ..< CHUNK_VOLUME:
          if voxels[linear] != EMPTY_VOXEL:
            let local_pos = from_linear(linear)
            let world_pos = vec3(
              chunk_id.x * 16 + local_pos.x,
              chunk_id.y * 16 + local_pos.y,
              chunk_id.z * 16 + local_pos.z
            )
            reconstructed[world_pos] = voxels[linear]

    # Apply all deltas for this chunk
    if chunk_id in self.voxels.chunk_deltas:
      for delta in self.voxels.chunk_deltas[chunk_id]:
        let changes = decode_delta(delta)
        for (local_pos, packed_voxel) in changes:
          let world_pos = vec3(
            chunk_id.x * 16 + local_pos.x,
            chunk_id.y * 16 + local_pos.y,
            chunk_id.z * 16 + local_pos.z
          )
          if packed_voxel == EMPTY_VOXEL:
            reconstructed.del(world_pos)
          else:
            reconstructed[world_pos] = packed_voxel

    # Build actual chunk state
    var actual: Table[Vector3, PackedVoxel]
    if chunk_id in self.voxels.chunks:
      for pos, info in self.voxels.chunks[chunk_id]:
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
      let has_snapshot = chunk_id in self.voxels.packed_chunks
      let delta_count = if chunk_id in self.voxels.chunk_deltas: self.voxels.chunk_deltas[chunk_id].len else: 0
      raise newException(AssertionDefect,
        &"Packed chunk verification failed for {self.id} chunk {chunk_id}:\n" &
        &"  has_snapshot={has_snapshot}, delta_count={delta_count}\n" &
        &"  actual_voxels={actual.len}, reconstructed_voxels={reconstructed.len}\n" &
        mismatches[0 .. min(mismatches.len - 1, 19)].join("\n"))

proc apply_delta_update*(self: Build, chunk_id: Vector3, delta: DeltaUpdate) =
  ## Apply a delta update to local chunks (for network receive).
  ## Does NOT mark chunk as dirty since this is receiving data, not generating it.
  let changes = decode_delta(delta)

  for (local_pos, packed_voxel) in changes:
    let world_pos = vec3(
      chunk_id.x * 16 + local_pos.x,
      chunk_id.y * 16 + local_pos.y,
      chunk_id.z * 16 + local_pos.z
    )

    if packed_voxel == EMPTY_VOXEL:
      # Remove voxel
      if chunk_id in self.voxels.chunks and world_pos in self.voxels.chunks[chunk_id]:
        let info = self.voxels.chunks[chunk_id][world_pos]
        if info.kind != Hole:
          dec self.voxels.block_count
        self.voxels.chunks[chunk_id].del(world_pos)
    else:
      # Add/modify voxel
      let (color_idx, kind_ord) = unpack_voxel(packed_voxel)
      let color = action_colors[Colors(color_idx)]
      let kind = VoxelKind(kind_ord)

      # Ensure chunk exists
      if chunk_id notin self.voxels.chunks:
        self.voxels.chunks[chunk_id] = self.voxels.create_chunk()
        self.expand_bounds_to_chunk(chunk_id)

      # Check if replacing existing voxel
      let existed = world_pos in self.voxels.chunks[chunk_id]
      if existed:
        let old_info = self.voxels.chunks[chunk_id][world_pos]
        if old_info.kind != Hole:
          dec self.voxels.block_count

      self.voxels.chunks[chunk_id][world_pos] = (kind, color)
      if kind != Hole:
        inc self.voxels.block_count

proc apply_snapshot*(self: Build, chunk_id: Vector3, snapshot: SnapshotData) =
  ## Decode a snapshot and apply to local chunks (for network receive).
  ## Does NOT mark chunk as dirty since this is receiving data, not generating it.
  if snapshot.data.len == 0:
    return

  let voxels = decode_chunk(snapshot)

  # Clear existing chunk if present
  if chunk_id in self.voxels.chunks:
    let chunk = self.voxels.chunks[chunk_id]
    for pos, info in chunk:
      if info.kind != Hole:
        dec self.voxels.block_count
    self.voxels.chunks.del(chunk_id)
    chunk.destroy

  # Check if the packed chunk has any voxels
  var has_voxels = false
  for v in voxels:
    if v != EMPTY_VOXEL:
      has_voxels = true
      break

  if has_voxels:
    self.voxels.chunks[chunk_id] = self.voxels.create_chunk()
    self.expand_bounds_to_chunk(chunk_id)

    for linear in 0 ..< CHUNK_VOLUME:
      let packed_voxel = voxels[linear]
      if packed_voxel != EMPTY_VOXEL:
        let (color_idx, kind_ord) = unpack_voxel(packed_voxel)
        let pos = from_linear(linear)
        let world_pos = vec3(
          chunk_id.x * 16 + pos.x,
          chunk_id.y * 16 + pos.y,
          chunk_id.z * 16 + pos.z
        )
        let color = action_colors[Colors(color_idx)]
        let kind = VoxelKind(kind_ord)
        self.voxels.chunks[chunk_id][world_pos] = (kind, color)
        if kind != Hole:
          inc self.voxels.block_count

proc apply_chunk_with_deltas*(self: Build, chunk_id: Vector3) =
  ## Apply snapshot and any existing deltas for a chunk.
  ## Used when a new chunk is first synced from network.
  if chunk_id in self.voxels.packed_chunks:
    self.apply_snapshot(chunk_id, self.voxels.packed_chunks[chunk_id])

  # Apply any deltas that arrived with the chunk
  if chunk_id in self.voxels.chunk_deltas:
    for delta in self.voxels.chunk_deltas[chunk_id]:
      self.apply_delta_update(chunk_id, delta)

proc clear_chunk*(self: Build, chunk_id: Vector3) =
  ## Efficiently clear an entire chunk by deleting it from the table.
  ## This sends a single Unassign message instead of many individual voxel deletes.
  if chunk_id in self.voxels.chunks:
    let chunk = self.voxels.chunks[chunk_id]
    for pos, info in chunk:
      if info.kind != Hole:
        dec self.voxels.block_count
    self.voxels.chunks.del(chunk_id)
    chunk.destroy
    if packed_chunks_enabled():
      self.voxels.dirty_chunks.incl(chunk_id)

method on_begin_move*(
    self: Build, direction: Vector3, steps: float, move_mode: int
): Callback =
  let move = self.is_moving(move_mode)
  if move:
    let steps = steps.float
    var duration = 0.0
    let
      moving = self.transform.basis.xform(direction) / self.scale
      finish = self.transform.origin + moving * steps
      finish_time = 1.0 / self.speed * steps

    result = proc(delta: float, _: MonoTime): TaskStates =
      duration += delta
      if duration >= finish_time:
        self.transform_value.origin = finish
        return Done
      else:
        self.transform_value.origin =
          self.transform.origin + (moving * self.speed * delta)

        return Running
  else:
    if self.speed == 0:
      self.voxels_per_frame = float.high
    else:
      self.voxels_remaining_this_frame = self.speed
      self.voxels_per_frame = self.speed
    var count = 0

    result = proc(delta: float, timeout: MonoTime): TaskStates =
      while count.float < steps and self.voxels_remaining_this_frame >= 1 and
          get_mono_time() < timeout:
        if steps < 1:
          self.draw_transform =
            self.draw_transform.translated(direction * steps)
        else:
          self.draw_transform = self.draw_transform.translated(direction)
        inc count
        self.voxels_remaining_this_frame -= 1
        self.drop_block()

      if count.float >= steps: NextTask else: Running

method on_begin_turn*(
    self: Build, axis: Vector3, degrees: float, lean: bool, move_mode: int
): Callback =
  let map =
    if lean:
      {LEFT: BACK, RIGHT: FORWARD, BACK: RIGHT, FORWARD: LEFT}.to_table
    else:
      {LEFT: UP, RIGHT: DOWN, UP: RIGHT, DOWN: LEFT}.to_table
  let axis = map[axis]
  let move = self.is_moving(move_mode)
  if move:
    self.voxels_per_frame = 0
    var duration = 0.0
    let axis = self.transform.basis.orthonormalized.xform(axis)
    let scale = self.scale
    var final_transform = self.transform
    final_transform.basis = final_transform.basis
      .rotated(axis, deg_to_rad(degrees)).orthonormalized
      .scaled(vec3(scale, scale, scale))

    result = proc(delta: float, _: MonoTime): TaskStates =
      duration += delta
      self.transform_value.basis = self.transform.basis.rotated(
        axis, deg_to_rad(degrees * delta * self.speed)
      )

      if duration <= 1.0 / self.speed:
        Running
      else:
        self.transform = final_transform
        Done
  else:
    let axis = self.draw_transform.basis.xform(axis)
    self.draw_transform_value.basis =
      self.draw_transform.basis.rotated(axis, deg_to_rad(degrees))

    self.draw_transform = self.draw_transform.orthonormalized()

proc reset_state*(self: Build) =
  self.init_shared
  self.draw_transform = Transform.init
  self.transform = self.start_transform

method reset*(self: Build) =
  debug "resetting build", id = self.id
  self.transform = self.start_transform
  self.color = self.start_color
  self.speed = 1
  self.scale = 1

  self.global_flags += Resetting
  self.global_flags += Visible
  self.reset_state()

  let chunks = self.voxels.chunks.value
  for chunk_id, chunk in chunks:
    self.voxels.chunks.del(chunk_id)
    chunk.destroy

  # Clear packed chunk data to avoid stale snapshots/deltas
  if packed_chunks_enabled():
    let packed = self.voxels.packed_chunks.value
    for chunk_id in packed.keys:
      self.voxels.packed_chunks.del(chunk_id)
    let deltas = self.voxels.chunk_deltas.value
    for chunk_id in deltas.keys:
      self.voxels.chunk_deltas.del(chunk_id)
    self.voxels.last_snapshot.clear
    self.voxels.dirty_chunks.clear

  self.units.clear()
  self.global_flags -= Resetting
  self.restore_edits
  self.draw(vec3(), (Computed, self.start_color))

method ensure_visible*(self: Build) =
  # It's possible for a build to have no blocks of its own if has children with
  # blocks. However, if the script fails or is changed to remove its children,
  # the unit will still exist but will have no presence in the world, and is
  # therefor impossible to select or modify. In that case we want to draw a
  # single block.
  if self.units.len == 0 and
      not self.voxels.chunks.any_it(
        it.value.any_it(it.value.color != action_colors[Eraser])
      ):
    let color =
      if self.start_color == action_colors[Eraser]:
        action_colors[Blue]
      else:
        self.start_color
    self.draw(vec3(), (Computed, color))

method destroy*(self: Build) =
  self.destroy_impl

proc init*(
    _: type Build,
    id = "build_" & generate_id(),
    transform = Transform.init,
    color = default_color,
    clone_of: Unit = nil,
    global = true,
    bot_collisions = true,
    parent: Unit = nil,
): Build =
  let voxel_id = id & ".voxels"
  let voxels = VoxelStore.init(
    id = voxel_id,
    disable_packed = not packed_chunks_enabled(),
  )
  var self = Build(
    id: id,
    voxels: voxels,
    start_transform: transform,
    draw_transform_value: ~(Transform.init, flags = {}),
    start_color: color,
    drawing: true,
    bounds_value: ~init_aabb(vec3(), vec3(-1, -1, -1)),
    speed: 1.0,
    clone_of: clone_of,
    bot_collisions: bot_collisions,
    parent: parent,
  )

  self.init_unit

  if global:
    self.global_flags += Global
  self.reset()
  result = self

proc init_voxels_if_needed*(self: Build) =
  ## Initialize voxels if nil (happens when Build is synced between threads)
  if self.voxels.isNil:
    let voxel_id = self.id & ".voxels"
    let ctx = Zen.thread_ctx
    self.voxels = VoxelStore(
      id: voxel_id,
      disable_packed: not packed_chunks_enabled(),
      ctx: ctx,
      chunks: ZenTable[Vector3, Chunk](ctx[voxel_id & ".chunks"]),
      packed_chunks: ZenTable[Vector3, SnapshotData](ctx[voxel_id & ".packed_chunks"]),
      chunk_deltas: ZenTable[Vector3, ZenSeq[DeltaUpdate]](ctx[voxel_id & ".chunk_deltas"]),
    )

method worker_thread_joined*(self: Build) =
  proc_call worker_thread_joined(Unit(self))

  self.init_voxels_if_needed()

  # Only clients need to apply packed chunks/deltas received from server
  # Servers create these directly from chunks, so no need to apply
  if packed_chunks_enabled() and (state.isNil or Server notin state.local_flags):
    # Helper to set up delta watch for a chunk
    proc watch_chunk_deltas(chunk_id: Vector3, delta_seq: ZenSeq[DeltaUpdate]) =
      delta_seq.watch:
        if added:
          self.apply_delta_update(chunk_id, change.item)

    # Process any snapshots that arrived before the watch was set up
    for chunk_id, snapshot in self.voxels.packed_chunks:
      self.apply_snapshot(chunk_id, snapshot)

    # Process any deltas that arrived before the watch was set up
    for chunk_id, delta_seq in self.voxels.chunk_deltas:
      if delta_seq.is_nil:
        continue
      for delta in delta_seq:
        self.apply_delta_update(chunk_id, delta)
      watch_chunk_deltas(chunk_id, delta_seq)

    self.voxels.packed_chunks.watch:
      if added:
        self.apply_snapshot(change.item.key, change.item.value)
      elif removed and change.item.key in self.voxels.chunks:
        # Chunk was deleted remotely
        let chunk = self.voxels.chunks[change.item.key]
        for pos, info in chunk:
          if info.kind != Hole:
            dec self.voxels.block_count
        self.voxels.chunks.del(change.item.key)
        chunk.destroy

    self.voxels.chunk_deltas.watch:
      if added:
        # New chunk delta seq - apply existing deltas and set up watch
        let chunk_id = change.item.key
        let delta_seq = change.item.value
        if not delta_seq.is_nil:
          for delta in delta_seq:
            self.apply_delta_update(chunk_id, delta)
          watch_chunk_deltas(chunk_id, delta_seq)

method main_thread_joined*(self: Build) =
  proc_call main_thread_joined(Unit(self))

  self.init_voxels_if_needed()

  # Main thread reconstructs chunks from packed_chunks/chunk_deltas
  if packed_chunks_enabled():
    # Helper to set up delta watch for a chunk
    proc watch_chunk_deltas(chunk_id: Vector3, delta_seq: ZenSeq[DeltaUpdate]) =
      delta_seq.watch:
        if added:
          self.apply_delta_update(chunk_id, change.item)

    # Process any snapshots that arrived before the watch was set up
    for chunk_id, snapshot in self.voxels.packed_chunks:
      self.apply_snapshot(chunk_id, snapshot)

    # Process any deltas that arrived before the watch was set up
    for chunk_id, delta_seq in self.voxels.chunk_deltas:
      if delta_seq.is_nil:
        continue
      for delta in delta_seq:
        self.apply_delta_update(chunk_id, delta)
      watch_chunk_deltas(chunk_id, delta_seq)
    self.voxels.packed_chunks.watch:
      if added:
        self.apply_snapshot(change.item.key, change.item.value)
      elif removed and change.item.key in self.voxels.chunks:
        # Chunk was deleted remotely
        let chunk = self.voxels.chunks[change.item.key]
        for pos, info in chunk:
          if info.kind != Hole:
            dec self.voxels.block_count
        self.voxels.chunks.del(change.item.key)
        chunk.destroy

    self.voxels.chunk_deltas.watch:
      if added:
        # New chunk delta seq - apply existing deltas and set up watch
        let chunk_id = change.item.key
        let delta_seq = change.item.value
        if not delta_seq.is_nil:
          for delta in delta_seq:
            self.apply_delta_update(chunk_id, delta)
          watch_chunk_deltas(chunk_id, delta_seq)

  self.local_flags.watch:
    if Hover.added and state.tool == CodeMode:
      if Playing notin state.local_flags and
          TouchControls notin state.local_flags:
        let root = self.find_root(true)
        root.walk_tree proc(unit: Unit) =
          unit.local_flags += Highlight
    elif Hover.removed:
      let root = self.find_root(true)
      root.walk_tree proc(unit: Unit) =
        unit.local_flags -= Highlight
    if TargetMoved.touched:
      let length = (
        self.target_point * self.target_normal - last_point * self.target_normal
      ).length

      if state.skip_block_paint:
        state.skip_block_paint = false
      elif (
        state.draw_unit_id == self.id and self.target_normal == draw_normal and
        length <= 5 and self.target_point != skip_point and
        state.tool != PlaceBot
      ):
        if SecondaryDown in state.local_flags:
          self.remove
        elif PrimaryDown in state.local_flags:
          self.fire

    if change.item in {TargetMoved, Hover} and state.tool == PlaceBot:
      if self.target_normal == UP:
        state.push_flag BlockTargetVisible
      else:
        state.pop_flag BlockTargetVisible

  # self.local_flags.watch:
  #   if Hover.added:
  #     if PrimaryDown in state.local_flags:
  #       state.draw_unit_id = self.id
  #       self.fire
  #     elif SecondaryDown in state.local_flags:
  #       state.draw_unit_id = self.id
  #       self.remove

  state.local_flags.watch:
    if Hover in self.local_flags and ViewportFocused in state.local_flags:
      if PrimaryDown.added:
        state.draw_unit_id = self.id
        self.fire
      elif SecondaryDown.added:
        state.draw_unit_id = self.id
        self.remove
    if PrimaryDown.removed or SecondaryDown.removed:
      state.draw_unit_id = ""
      last_point = vec3()
    if Playing.added:
      self.local_flags -= Highlight
    elif Playing.removed:
      if Hover in self.local_flags:
        self.local_flags += Highlight

method on_collision*(self: Build, partner: Model, normal: Vector3) =
  self.collisions.add (partner.id, normal)

method off_collision*(self: Unit, partner: Model) =
  if self.collisions.valid:
    for collision in self.collisions.value.dup:
      if collision.id == partner.id:
        self.collisions -= collision

method clone*(self: Build, clone_to: Unit, id: string): Unit =
  var transform = clone_to.transform
  var global = true
  if clone_to of Build:
    transform = Build(clone_to).draw_transform
    global = false

  # we need this off for Potato Zombies, but on for the
  # tutorials. Make it configurable somehow.
  let bot_collisions = true #not (clone_to of Bot)
  let clone = Build.init(
    id = id,
    transform = transform,
    clone_of = self,
    global = global,
    color = self.start_color,
    bot_collisions = bot_collisions,
    parent = clone_to,
  )

  for loc, info in self.shared.edits[self.id]:
    if info.kind != Hole and loc notin clone.shared.edits[clone.id]:
      clone.add_voxel(loc, info)

  clone.restore_edits
  result = clone

when is_main_module:
  import unittest, states
  type Node = ref object of RootObj

  var b = Build.init

  b.draw vec3(1, 1, 1), (Computed, Color())
  assert vec3(1, 1, 1) in b.voxels.chunks[vec3(0, 0, 0)]
  b.draw vec3(17, 17, 17), (Computed, Color())
  assert vec3(17, 17, 17) in b.voxels.chunks[vec3(1, 1, 1)]
  var c = Build.init(transform = Transform(origin: vec3(5, 5, 5)))
  c.parent = b

  c.draw vec3(14, 14, 14), (Manual, Color())
  c.local_flags += Hover
