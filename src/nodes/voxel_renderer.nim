## VoxelRenderer - Renders voxels to Godot VoxelTerrain
##
## Handles buffer management and Godot integration for voxel rendering.
## Watches VoxelStore's packed_chunks and chunk_deltas to trigger rendering.

import std/[tables, sets]
import pkg/[model_citizen, godot]
import godotapi/[voxel_buffer, voxel_tool, voxel_tool_terrain]
import pkg/core/[vector3]
import core
import models/[packed_chunks, colors]

const CHUNK_BUFFER_BLOCK_THRESHOLD* = 10000
  ## Use set_voxel for changes with this many blocks or fewer

type VoxelRenderer* = ref object
  store*: VoxelStore
  model*: Unit
  voxel_tool*: VoxelToolTerrain

  # Buffer management
  buffers: Table[Vector3, VoxelBuffer]
  pending_paste: HashSet[Vector3]
  rendered_snapshot_len: Table[Vector3, int]

  # Stats
  buffer_creates*: int
  paste_count*: int

proc get_buffer*(self: VoxelRenderer, chunk_id: Vector3): VoxelBuffer =
  if chunk_id notin self.buffers:
    self.buffer_creates.inc
    let buffer = gdnew[VoxelBuffer]()
    buffer.create(16, 16, 16)
    buffer.fill(0)
    self.buffers[chunk_id] = buffer
  result = self.buffers[chunk_id]

proc remove_buffer*(self: VoxelRenderer, chunk_id: Vector3) =
  self.buffers.del(chunk_id)
  self.pending_paste.excl(chunk_id)
  self.rendered_snapshot_len.del(chunk_id)

proc apply_to_buffer(
    buffer: VoxelBuffer, voxels: array[CHUNK_VOLUME, PackedVoxel]
) =
  for i, packed in voxels:
    if packed != EMPTY_VOXEL:
      let (color_index, _) = unpack_voxel(packed)
      let pos = from_linear(i)
      buffer.set_voxel(color_index.int64, pos.x.int64, pos.y.int64, pos.z.int64)

proc apply_delta_to_buffer(
    buffer: VoxelBuffer, changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]]
) =
  for (local_pos, packed) in changes:
    let color_index =
      if packed == EMPTY_VOXEL:
        0
      else:
        unpack_voxel(packed)[0]
    buffer.set_voxel(
      color_index.int64, local_pos.x.int64, local_pos.y.int64, local_pos.z.int64
    )

proc paste_buffer(self: VoxelRenderer, chunk_id: Vector3) =
  if chunk_id notin self.buffers:
    return

  let buffer = self.buffers[chunk_id]
  let chunk_origin = chunk_id * 16.0

  self.paste_count.inc
  self.voxel_tool.paste(chunk_origin, buffer, 1, -1)

proc render_snapshot*(self: VoxelRenderer, chunk_id: Vector3) =
  if chunk_id notin self.store.packed_chunks:
    return

  let snapshot = self.store.packed_chunks[chunk_id]
  if snapshot.is_empty:
    return

  # Skip if we've already rendered this exact snapshot
  let snapshot_len = snapshot.data.len
  if chunk_id in self.rendered_snapshot_len and
      self.rendered_snapshot_len[chunk_id] == snapshot_len:
    return
  self.rendered_snapshot_len[chunk_id] = snapshot_len

  let voxels = decode_chunk(snapshot)
  let chunk_origin = chunk_id * 16.0

  # Count non-empty voxels to decide rendering method
  var voxel_count = 0
  for packed in voxels:
    if packed != EMPTY_VOXEL:
      voxel_count.inc

  # Use set_voxel directly for small changes
  if voxel_count <= CHUNK_BUFFER_BLOCK_THRESHOLD:
    for i, packed in voxels:
      if packed != EMPTY_VOXEL:
        let (color_index, _) = unpack_voxel(packed)
        let local_pos = from_linear(i)
        let world_pos = chunk_origin + local_pos
        self.voxel_tool.set_voxel(world_pos, color_index.int64)
  else:
    let buffer = self.get_buffer(chunk_id)
    apply_to_buffer(buffer, voxels)
    self.pending_paste.incl(chunk_id)

proc render_delta*(self: VoxelRenderer, chunk_id: Vector3, delta: DeltaUpdate) =
  let chunk_origin = chunk_id * 16.0
  let changes = decode_delta(delta)

  # Use set_voxel directly for small changes
  if changes.len <= CHUNK_BUFFER_BLOCK_THRESHOLD:
    for (local_pos, packed) in changes:
      let world_pos = chunk_origin + local_pos
      let color_index =
        if packed == EMPTY_VOXEL:
          0
        else:
          unpack_voxel(packed)[0]
      self.voxel_tool.set_voxel(world_pos, color_index.int64)
  else:
    let buffer = self.get_buffer(chunk_id)
    apply_delta_to_buffer(buffer, changes)
    self.pending_paste.incl(chunk_id)

proc flush*(self: VoxelRenderer) =
  if self.pending_paste.len == 0:
    return

  # Paste all pending buffers (paste handles mesh notification)
  for chunk_id in self.pending_paste:
    self.paste_buffer(chunk_id)
  self.pending_paste.clear

proc setup_watchers*(self: VoxelRenderer) =
  # Watch packed_chunks for snapshot updates
  self.store.packed_chunks.watch(self.model):
    let chunk_id = change.item.key
    if added:
      self.render_snapshot(chunk_id)

  # Watch chunk_deltas for new delta sequences, then watch each sequence
  self.store.chunk_deltas.watch(self.model):
    let chunk_id = change.item.key
    if added:
      change.item.value.watch(self.model):
        if added:
          self.render_delta(chunk_id, change.item)

proc init*(
    _: type VoxelRenderer,
    store: VoxelStore,
    model: Unit,
    voxel_tool: VoxelToolTerrain,
): VoxelRenderer =
  result = VoxelRenderer(store: store, model: model, voxel_tool: voxel_tool)
