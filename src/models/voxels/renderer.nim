## VoxelRenderer and direct voxel-tool rendering: painting snapshots/deltas into
## the terrain, the ASAP batching buffer, and the frame-animation byte fills
## (fill_chunk_type_bytes / fill_padded_chunk_bytes) plus the content-key helpers.
import std/[tables, monotimes, times, hashes]
import pkg/godot except print, Color
import godotapi/[voxel_buffer, voxel_tool]
import core
import models/colors
import ./codec

proc chunk_aabb(chunk_id: Vector3): AABB {.inline.} =
  init_aabb(chunk_id * ChunkDim, vec3(ChunkDim, ChunkDim, ChunkDim))

type SlotCache = Table[int, int64]
  ## Per-render-call memo: a chunk has at most a few dozen distinct colors,
  ## but thousands of voxels — resolving each index once keeps the resolver
  ## (palette read + registry lookup) off the per-voxel path.

proc library_slot(
    resolver: ColorIndexResolver, color_idx: int, cache: var SlotCache
): int64 {.inline.} =
  ## The engine voxel type id for a packed color index. Named colors are
  ## their own library slots; static palette indices need the resolver.
  if color_idx < STATIC_COLOR_BASE or resolver.is_nil:
    return color_idx.int64
  cache.with_value(color_idx, slot):
    return slot[]
  result = resolver(color_idx)
  cache[color_idx] = result

{.push checks: off.}
proc fill_chunk_type_bytes*(
    bytes: PoolByteArray,
    snapshot: SnapshotData,
    resolver: ColorIndexResolver = nil,
): int {.discardable.} =
  ## Resolved engine voxel type ids for a chunk snapshot, as u16 LE values
  ## in `linear_position` order — the payload VoxelTerrain.set_block_voxel_data
  ## expects. `bytes` must be pre-sized to CHUNK_VOLUME * 2. Returns the
  ## non-empty voxel count. An empty snapshot fills zeroes (chunk erase).
  assert bytes.len == CHUNK_VOLUME * 2
  let voxels = decode_chunk(snapshot)
  var slot_cache: SlotCache
  var ids: array[CHUNK_VOLUME, uint16]
  for linear in 0 ..< CHUNK_VOLUME:
    let packed_voxel = voxels[linear]
    if not packed_voxel.renders_as_air:
      let (color_idx, _) = unpack_voxel(packed_voxel)
      ids[linear] = uint16(resolver.library_slot(color_idx, slot_cache))
      inc result
  for i, b in bytes.mpairs:
    let v = ids[i shr 1]
    b = if (i and 1) == 0: uint8(v and 0xff) else: uint8(v shr 8)

type DecodedChunks* = Table[Vector3, ref array[CHUNK_VOLUME, PackedVoxel]]
  ## Lazily decoded chunks of one frame — the working set for shell-aware
  ## key computation. Callers memoize per frame index and decode on demand
  ## (decode_into), so key work can be spread under a time budget.

proc decode_into*(
    decoded: var DecodedChunks, frame: FrameData, chunk_id: Vector3
) =
  ## Ensure `chunk_id` is decoded (nil entry = chunk absent from the frame,
  ## cached so the lookup doesn't repeat).
  if chunk_id in decoded:
    return
  if chunk_id in frame.chunks:
    var arr = new(array[CHUNK_VOLUME, PackedVoxel])
    arr[] = decode_chunk(frame.chunks[chunk_id])
    decoded[chunk_id] = arr
  else:
    decoded[chunk_id] = nil

proc chunk_frame_key*(
    decoded: var DecodedChunks, frame: FrameData, chunk_id: Vector3
): Hash =
  ## Shell-aware content key for one chunk of a frame: the mesher culls
  ## border faces (and bakes occlusion) against neighboring blocks, so a
  ## chunk's mesh is a function of its own 16³ content PLUS a 1-voxel shell
  ## from its neighbors — the key hashes the padded 18³ region. Identical
  ## keys then imply identical meshes; central-only keys would reuse meshes
  ## with wrong borders when a neighbor differs between frames.
  ##
  ## Hot: runs on the main thread inside the frame-apply budget. The inner
  ## loop stays free of table lookups — neighbor arrays resolve once.
  var neighbors: array[27, ref array[CHUNK_VOLUME, PackedVoxel]]
  for dx in 0 .. 2:
    for dy in 0 .. 2:
      for dz in 0 .. 2:
        let key = vec3(
          chunk_id.x + float(dx - 1),
          chunk_id.y + float(dy - 1),
          chunk_id.z + float(dz - 1),
        )
        decoded.decode_into(frame, key)
        neighbors[dx * 9 + dy * 3 + dz] = decoded[key]

  # per-axis padded coordinate -> (neighbor offset 0..2, local coordinate)
  var axis_chunk {.global.}: array[ChunkDim + 2, int]
  var axis_local {.global.}: array[ChunkDim + 2, int]
  once:
    for i in 0 ..< ChunkDim + 2:
      let c = i - 1
      if c < 0:
        axis_chunk[i] = 0
        axis_local[i] = ChunkDim - 1
      elif c >= ChunkDim:
        axis_chunk[i] = 2
        axis_local[i] = 0
      else:
        axis_chunk[i] = 1
        axis_local[i] = c

  var h: Hash = 0
  for xi in 0 ..< ChunkDim + 2:
    let cx = axis_chunk[xi] * 9
    let lx = axis_local[xi] * ChunkDim * ChunkDim
    for yi in 0 ..< ChunkDim + 2:
      let cy = axis_chunk[yi] * 3
      let ly = axis_local[yi] * ChunkDim
      for zi in 0 ..< ChunkDim + 2:
        let arr = neighbors[cx + cy + axis_chunk[zi]]
        var v =
          if arr.is_nil:
            EMPTY_VOXEL
          else:
            arr[lx + ly + axis_local[zi]]
        if v.renders_as_air:
          v = EMPTY_VOXEL
        h = h !& v.int
  !$h

proc fill_padded_chunk_bytes*(
    bytes: PoolByteArray,
    decoded: var DecodedChunks,
    frame: FrameData,
    chunk_id: Vector3,
    resolver: ColorIndexResolver = nil,
    sealed = false,
) =
  ## The payload for VoxelTerrain.request_frame_mesh: the chunk's resolved
  ## engine type ids PLUS its 1-voxel shell, u16 LE in x-major order over
  ## the padded (ChunkDim+2)³ region. Sealed builds get an air shell —
  ## border faces always bake, so any mix of displayed frames is closed.
  ## Unsealed builds get the real neighbor shell from the same frame's
  ## data: the bake is a pure function of frame data, valid regardless of
  ## what any neighbor currently displays.
  const PADDED = ChunkDim + 2
  assert bytes.len == PADDED * PADDED * PADDED * 2
  var neighbors: array[27, ref array[CHUNK_VOLUME, PackedVoxel]]
  if sealed:
    decoded.decode_into(frame, chunk_id)
    neighbors[13] = decoded[chunk_id] # 1*9 + 1*3 + 1
  else:
    for dx in 0 .. 2:
      for dy in 0 .. 2:
        for dz in 0 .. 2:
          let key = vec3(
            chunk_id.x + float(dx - 1),
            chunk_id.y + float(dy - 1),
            chunk_id.z + float(dz - 1),
          )
          decoded.decode_into(frame, key)
          neighbors[dx * 9 + dy * 3 + dz] = decoded[key]

  var axis_chunk {.global.}: array[PADDED, int]
  var axis_local {.global.}: array[PADDED, int]
  once:
    for i in 0 ..< PADDED:
      let c = i - 1
      if c < 0:
        axis_chunk[i] = 0
        axis_local[i] = ChunkDim - 1
      elif c >= ChunkDim:
        axis_chunk[i] = 2
        axis_local[i] = 0
      else:
        axis_chunk[i] = 1
        axis_local[i] = c

  var slot_cache: SlotCache
  var ids: array[PADDED * PADDED * PADDED, uint16]
  var i = 0
  for xi in 0 ..< PADDED:
    let cx = axis_chunk[xi] * 9
    let lx = axis_local[xi] * ChunkDim * ChunkDim
    for yi in 0 ..< PADDED:
      let cy = axis_chunk[yi] * 3
      let ly = axis_local[yi] * ChunkDim
      for zi in 0 ..< PADDED:
        let arr = neighbors[cx + cy + axis_chunk[zi]]
        if not arr.is_nil:
          let packed_voxel = arr[lx + ly + axis_local[zi]]
          if not packed_voxel.renders_as_air:
            let (color_idx, _) = unpack_voxel(packed_voxel)
            ids[i] = uint16(resolver.library_slot(color_idx, slot_cache))
        inc i
  for bi, b in bytes.mpairs:
    let v = ids[bi shr 1]
    b = if (bi and 1) == 0: uint8(v and 0xff) else: uint8(v shr 8)

{.pop.}

proc render_snapshot_direct*(
    voxel_tool: VoxelTool,
    chunk_id: Vector3,
    snapshot: SnapshotData,
    resolver: ColorIndexResolver = nil,
): int {.discardable.} =
  ## Render a chunk's snapshot into the terrain. Checks
  ## `is_area_editable` first: if the chunk's data block is fully
  ## loaded we use the cheap per-voxel `set_voxel`; otherwise we fall
  ## back to a one-chunk `paste`, because `set_voxel` silently no-ops
  ## for chunks the terrain hasn't fully loaded yet.
  if snapshot.data.len == 0:
    return 0
  let voxels = decode_chunk(snapshot)
  let chunk_min = chunk_id * ChunkDim
  var slot_cache: SlotCache
  if voxel_tool.is_area_editable(chunk_aabb(chunk_id)):
    for linear in 0 ..< CHUNK_VOLUME:
      let packed_voxel = voxels[linear]
      if packed_voxel != EMPTY_VOXEL:
        let local_pos = from_linear(linear)
        let (color_idx, _) = unpack_voxel(packed_voxel)
        voxel_tool.set_voxel(
          chunk_min + local_pos,
          resolver.library_slot(color_idx, slot_cache),
        )
        inc result
  else:
    let buffer = gdnew[VoxelBuffer]()
    buffer.create(ChunkDim, ChunkDim, ChunkDim)
    buffer.fill(0)
    for linear in 0 ..< CHUNK_VOLUME:
      let packed_voxel = voxels[linear]
      if packed_voxel != EMPTY_VOXEL:
        let local_pos = from_linear(linear)
        let (color_idx, _) = unpack_voxel(packed_voxel)
        buffer.set_voxel(
          resolver.library_slot(color_idx, slot_cache),
          local_pos.x.int64, local_pos.y.int64, local_pos.z.int64,
        )
        inc result
    voxel_tool.paste(chunk_min, buffer, 1, 0)

proc render_snapshot_replace*(
    voxel_tool: VoxelTool,
    chunk_id: Vector3,
    snapshot: SnapshotData,
    resolver: ColorIndexResolver = nil,
): int {.discardable.} =
  ## Render a chunk snapshot REPLACING whatever the chunk showed before —
  ## cells empty in the snapshot are cleared. Always paste-based, because
  ## paste overwrites every cell; the additive fast path in
  ## render_snapshot_direct leaves stale voxels behind (frame flips need
  ## replacement semantics).
  let voxels = decode_chunk(snapshot)
  let chunk_min = chunk_id * ChunkDim
  var slot_cache: SlotCache
  let buffer = gdnew[VoxelBuffer]()
  buffer.create(ChunkDim, ChunkDim, ChunkDim)
  buffer.fill(0)
  for linear in 0 ..< CHUNK_VOLUME:
    let packed_voxel = voxels[linear]
    if packed_voxel != EMPTY_VOXEL:
      let local_pos = from_linear(linear)
      let (color_idx, _) = unpack_voxel(packed_voxel)
      buffer.set_voxel(
        resolver.library_slot(color_idx, slot_cache),
        local_pos.x.int64, local_pos.y.int64, local_pos.z.int64,
      )
      inc result
  voxel_tool.paste(chunk_min, buffer, 1, 0)

proc render_delta_direct*(
    voxel_tool: VoxelTool,
    chunk_id: Vector3,
    delta: DeltaUpdate,
    resolver: ColorIndexResolver = nil,
): int {.discardable.} =
  ## Render a delta into the terrain. Same fast/slow split as
  ## render_snapshot_direct — `set_voxel` for editable chunks, `paste`
  ## fallback for chunks the terrain doesn't yet consider fully
  ## loaded (where `set_voxel` would silently drop the write).
  if delta.data.len == 0:
    return 0
  let changes = decode_delta(delta)
  let chunk_min = chunk_id * ChunkDim
  var slot_cache: SlotCache
  let editable = voxel_tool.is_area_editable(chunk_aabb(chunk_id))
  if editable:
    for (local_pos, packed_voxel) in changes:
      let world_pos = chunk_min + local_pos
      if packed_voxel == EMPTY_VOXEL:
        voxel_tool.set_voxel(world_pos, 0)
      else:
        let (color_idx, _) = unpack_voxel(packed_voxel)
        voxel_tool.set_voxel(
          world_pos, resolver.library_slot(color_idx, slot_cache)
        )
      inc result
  else:
    let buffer = gdnew[VoxelBuffer]()
    buffer.create(ChunkDim, ChunkDim, ChunkDim)
    buffer.fill(0)
    for (local_pos, packed_voxel) in changes:
      if packed_voxel == EMPTY_VOXEL:
        # paste with use_mask=true treats 0 as skip, so eraser writes
        # need to go through set_voxel separately. Best-effort; if the
        # area isn't editable, the eraser won't take effect until a
        # later render pass.
        voxel_tool.set_voxel(chunk_min + local_pos, 0)
      else:
        let (color_idx, _) = unpack_voxel(packed_voxel)
        buffer.set_voxel(
          resolver.library_slot(color_idx, slot_cache),
          local_pos.x.int64, local_pos.y.int64, local_pos.z.int64,
        )
        inc result
    voxel_tool.paste(chunk_min, buffer, 1, 0)

proc erase_chunk_direct*(voxel_tool: VoxelTool, chunk_id: Vector3) =
  ## Clear a paged-out chunk from the terrain — the un-render counterpart of
  ## render_snapshot_direct. One zero-filled paste: the godot_voxel paste
  ## binding overwrites every cell (no use_mask — see ensure_buffer), which is
  ## exactly what an eraser wants, and it works whether or not the terrain
  ## considers the chunk editable.
  let chunk_min = chunk_id * ChunkDim
  let buffer = gdnew[VoxelBuffer]()
  buffer.create(ChunkDim, ChunkDim, ChunkDim)
  buffer.fill(0)
  voxel_tool.paste(chunk_min, buffer, 1, 0)

const ASAP_PASTE_INTERVAL = init_duration(seconds = 2)

proc init*(
    _: type VoxelRenderer,
    voxel_tool: VoxelTool,
    resolver: ColorIndexResolver = nil,
): VoxelRenderer =
  assert ?voxel_tool
  VoxelRenderer(voxel_tool: voxel_tool, resolver: resolver)

proc ensure_buffer(self: VoxelRenderer, chunk_id: Vector3) =
  let chunk_min = chunk_id * ChunkDim
  let chunk_max = chunk_min + vec3(ChunkDim - 1, ChunkDim - 1, ChunkDim - 1)

  if not ?self.buffer:
    self.min_pos = chunk_min
    self.max_pos = chunk_max
    self.buffer_size = vec3(ChunkDim, ChunkDim, ChunkDim)
    self.buffer = gdnew[VoxelBuffer]()
    self.buffer.create(ChunkDim, ChunkDim, ChunkDim)
    # Zero first — VoxelBuffer.create doesn't initialize cells, so any
    # cells voxel_tool.copy below doesn't touch would otherwise hold
    # uninitialized memory and get pasted back as spurious voxels.
    self.buffer.fill(0)
    # Pre-populate the buffer with the terrain's current state so the
    # paste at end_asap doesn't wipe voxels that were written before
    # ASAP began. (The godot_voxel paste binding doesn't expose
    # use_mask, so paste always overwrites every cell including the
    # untouched ones — pre-populating means "untouched" cells already
    # hold the correct existing values.)
    self.voxel_tool.copy(self.min_pos, self.buffer, 1)
  elif chunk_min.x < self.min_pos.x or chunk_min.y < self.min_pos.y or
      chunk_min.z < self.min_pos.z or chunk_max.x > self.max_pos.x or
      chunk_max.y > self.max_pos.y or chunk_max.z > self.max_pos.z:
    let new_min = vec3(
      min(chunk_min.x, self.min_pos.x),
      min(chunk_min.y, self.min_pos.y),
      min(chunk_min.z, self.min_pos.z),
    )
    let new_max = vec3(
      max(chunk_max.x, self.max_pos.x),
      max(chunk_max.y, self.max_pos.y),
      max(chunk_max.z, self.max_pos.z),
    )
    let new_size = new_max - new_min + vec3(1, 1, 1)

    let new_buffer = gdnew[VoxelBuffer]()
    new_buffer.create(new_size.x.int64, new_size.y.int64, new_size.z.int64)
    # Zero first; see note above in the fresh-buffer path.
    new_buffer.fill(0)
    # Pre-populate the new buffer's terrain region from the terrain,
    # then overlay our existing buffer's contents (which carry the
    # in-flight deltas) on top.
    self.voxel_tool.copy(new_min, new_buffer, 1)

    let offset = self.min_pos - new_min
    new_buffer.copy_channel_from_area(
      self.buffer, vec3(0, 0, 0), self.buffer_size, offset, 0
    )

    self.buffer = new_buffer
    self.min_pos = new_min
    self.max_pos = new_max
    self.buffer_size = new_size

proc buffer_snapshot*(
    self: VoxelRenderer,
    chunk_id: Vector3,
    snapshot: SnapshotData,
    replace = false,
): int {.discardable.} =
  ## Write a chunk snapshot into the ASAP buffer. With `replace`, the
  ## chunk's whole region is zeroed first: a REWRITTEN chunk (cleared and
  ## redrawn in one sync batch) must not inherit voxels the new content
  ## doesn't cover — the buffer is pre-populated from the terrain, so
  ## additive writes would resurrect them.
  if snapshot.data.len == 0:
    return
  self.ensure_buffer(chunk_id)
  if replace:
    let chunk_min = chunk_id * ChunkDim
    for x in 0 ..< ChunkDim:
      for y in 0 ..< ChunkDim:
        for z in 0 ..< ChunkDim:
          let buffer_pos = chunk_min + vec3(x.float, y.float, z.float) -
            self.min_pos
          self.buffer.set_voxel(
            0, buffer_pos.x.int64, buffer_pos.y.int64, buffer_pos.z.int64
          )
  var slot_cache: SlotCache
  let voxels = decode_chunk(snapshot)
  for linear in 0 ..< CHUNK_VOLUME:
    let packed_voxel = voxels[linear]
    if packed_voxel != EMPTY_VOXEL:
      let local_pos = from_linear(linear)
      let world_pos = chunk_id * ChunkDim + local_pos
      let buffer_pos = world_pos - self.min_pos
      let (color_idx, _) = unpack_voxel(packed_voxel)
      self.buffer.set_voxel(
        self.resolver.library_slot(color_idx, slot_cache), buffer_pos.x.int64,
        buffer_pos.y.int64, buffer_pos.z.int64,
      )
      inc result
  self.dirty = true

proc buffer_delta*(
    self: VoxelRenderer, chunk_id: Vector3, delta: DeltaUpdate
): int {.discardable.} =
  if delta.data.len == 0:
    return
  self.ensure_buffer(chunk_id)
  var slot_cache: SlotCache
  let changes = decode_delta(delta)
  for (local_pos, packed_voxel) in changes:
    let world_pos = chunk_id * ChunkDim + local_pos
    let buffer_pos = world_pos - self.min_pos
    if packed_voxel == EMPTY_VOXEL:
      self.buffer.set_voxel(
        0, buffer_pos.x.int64, buffer_pos.y.int64, buffer_pos.z.int64
      )
    else:
      let (color_idx, _) = unpack_voxel(packed_voxel)
      self.buffer.set_voxel(
        self.resolver.library_slot(color_idx, slot_cache), buffer_pos.x.int64,
        buffer_pos.y.int64, buffer_pos.z.int64,
      )
      inc result
  self.dirty = true

proc begin_asap*(self: VoxelRenderer) =
  # If a previous cycle's buffer wasn't pasted yet, paste it now
  # before clearing. Defensive: keeps the renderer robust against
  # rapid ASAP toggling.
  if ?self.buffer and self.dirty:
    self.voxel_tool.paste(self.min_pos, self.buffer, 1, 0)
  self.buffer = nil
  self.min_pos = vec3()
  self.max_pos = vec3()
  self.buffer_size = vec3()
  self.dirty = false
  self.asap_active = true
  # Backdate so the first dirty buffer paints on the next tick instead of
  # waiting a full interval — the initial draw shows immediately, then
  # sustained drawing batches at ASAP_PASTE_INTERVAL.
  self.last_paste_time = get_mono_time() - ASAP_PASTE_INTERVAL

proc buffer_erase*(self: VoxelRenderer, chunk_id: Vector3) =
  ## Zero a cleared chunk's region in the ASAP buffer. The buffer is
  ## pre-populated from the terrain when created, so without this a chunk
  ## cleared mid-stream gets its old content resurrected by the next paste.
  if not ?self.buffer:
    return
  let chunk_min = chunk_id * ChunkDim
  for x in 0 ..< ChunkDim:
    for y in 0 ..< ChunkDim:
      for z in 0 ..< ChunkDim:
        let pos = chunk_min + vec3(x.float, y.float, z.float) - self.min_pos
        if pos.x < 0 or pos.y < 0 or pos.z < 0 or
            pos.x >= self.buffer_size.x or pos.y >= self.buffer_size.y or
            pos.z >= self.buffer_size.z:
          continue
        self.buffer.set_voxel(0, pos.x.int64, pos.y.int64, pos.z.int64)
  self.dirty = true

proc tick*(self: VoxelRenderer, is_local: bool) =
  ## Periodic paste for local ASAP mode only (visual progress feedback).
  ## Remote ASAP buffers without periodic paste - final paste via end_asap().
  if self.asap_active and is_local:
    let now = get_mono_time()
    let elapsed = now - self.last_paste_time
    if elapsed >= ASAP_PASTE_INTERVAL and ?self.buffer and self.dirty:
      # The clock only advances when something pastes: an empty tick must
      # not consume begin_asap's backdate, or the run's first content ends
      # up waiting for end_asap — recognized a full sleep-park after the
      # script finishes drawing — instead of pasting on arrival.
      self.voxel_tool.paste(self.min_pos, self.buffer, 1, 0)
      self.dirty = false
      self.last_paste_time = now

proc end_asap*(self: VoxelRenderer) =
  if ?self.buffer and self.dirty:
    self.voxel_tool.paste(self.min_pos, self.buffer, 1, 0)
  self.buffer = nil
  self.min_pos = vec3()
  self.max_pos = vec3()
  self.buffer_size = vec3()
  self.dirty = false
  self.asap_active = false
