import std/[tables, sets, math]
import core, models/[units, voxels, states]
import ../types

const
  # World-space paging radii for partial clients. A chunk whose center comes
  # within `load_radius` of the player is requested from the server; a paged-in
  # chunk drifting past `unload_radius` is released (evicted locally + interest
  # retracted). The gap is hysteresis so chunks don't thrash at the boundary.
  load_radius = 192.0
  unload_radius = 288.0
  # Re-sweep cadence when the player hasn't crossed a chunk cell — catches new
  # builds and bounds growth without rechecking every frame.
  sweep_interval_frames = 60

type ChunkPager* = ref object
  ## Pages voxel chunks in and out as the player moves (partial clients only).
  ## The voxel tables are LAZY: units arrive with empty table handles, and the
  ## pager pulls nearby chunks with `request` / sheds far ones with `release`.
  # Per-build chunk ids we've asked for. A requested-but-missing key keeps a
  # per-key interest on the server, so an empty position pops in if someone
  # builds there — don't re-request it every sweep.
  requested: Table[string, HashSet[Vector3]]
  last_cell: Vector3
  primed: bool
  total_requested: int
  total_released: int

proc init*(_: type ChunkPager): ChunkPager =
  ChunkPager()

proc page_build(self: ChunkPager, build: Build, player_pos: Vector3) =
  if not ?build.voxels:
    # Tables not wired yet (unit still joining); a later sweep catches it.
    return
  let scale = if build.scale > 0: build.scale else: 1.0
  # Build-local voxel space (translation + scale; the voxel grid doesn't
  # rotate — same approximation as `local_to` everywhere else).
  let local = player_pos.local_to(build) / scale
  let load_r = load_radius / scale
  let unload_r = unload_radius / scale

  discard self.requested.has_key_or_put(build.id, HashSet[Vector3]())

  # Page out: paged-in chunks beyond the unload radius.
  var to_release: seq[Vector3]
  for chunk_id in self.requested[build.id]:
    let center = chunk_id * ChunkDim + ChunkSize * 0.5
    if (center - local).length > unload_r:
      to_release.add chunk_id
  for chunk_id in to_release:
    build.voxels.packed_chunks.release(chunk_id)
    build.voxels.chunk_deltas.release(chunk_id)
    self.requested[build.id].excl chunk_id
    inc self.total_released

  # Page in: chunks inside the load sphere, clamped to the build's bounds
  # (we don't know the table's shape — bounds prune the candidate grid, and
  # the server answers misses with a NACK that doubles as a subscription).
  let bounds = build.bounds
  if bounds.size == vec3():
    return
  let lo = vec3(
    max(bounds.position.x, local.x - load_r),
    max(bounds.position.y, local.y - load_r),
    max(bounds.position.z, local.z - load_r),
  )
  let hi = vec3(
    min(bounds.position.x + bounds.size.x, local.x + load_r),
    min(bounds.position.y + bounds.size.y, local.y + load_r),
    min(bounds.position.z + bounds.size.z, local.z + load_r),
  )
  if lo.x > hi.x or lo.y > hi.y or lo.z > hi.z:
    return
  let cmin = (lo / ChunkSize).floor
  let cmax = (hi / ChunkSize).floor
  for x in cmin.x.int .. cmax.x.int:
    for y in cmin.y.int .. cmax.y.int:
      for z in cmin.z.int .. cmax.z.int:
        let chunk_id = vec3(x.float, y.float, z.float)
        if chunk_id in self.requested[build.id]:
          continue
        let center = chunk_id * ChunkDim + ChunkSize * 0.5
        if (center - local).length <= load_r:
          build.voxels.packed_chunks.request(chunk_id)
          build.voxels.chunk_deltas.request(chunk_id)
          self.requested[build.id].incl chunk_id
          inc self.total_requested

proc tick*(self: ChunkPager) =
  ## Run from the client worker loop. Cheap when idle: a full sweep only on
  ## chunk-cell crossings and every `sweep_interval_frames`.
  if SERVER in state.local_flags:
    return
  let player = state.player
  if player.is_nil:
    return
  let pos = player.position
  let cell = (pos / ChunkSize).floor
  if self.primed and cell == self.last_cell and
      state.frame_count mod sweep_interval_frames != 0:
    return
  self.primed = true
  self.last_cell = cell

  let before_requested = self.total_requested
  let before_released = self.total_released
  var seen: HashSet[string]
  state.units.value.walk_tree proc(unit: Unit) {.gcsafe.} =
    if unit of Build:
      seen.incl unit.id
      self.page_build(Build(unit), pos)
  # Builds that disappeared take their bookkeeping with them.
  var gone: seq[string]
  for build_id in self.requested.keys:
    if build_id notin seen:
      gone.add build_id
  for build_id in gone:
    self.requested.del build_id

  if self.total_requested != before_requested or
      self.total_released != before_released:
    info "chunk pager",
      requested = self.total_requested - before_requested,
      released = self.total_released - before_released,
      total_requested = self.total_requested,
      total_released = self.total_released
