import
  std/[
    tables, sets, options, sequtils, math, monotimes, times, sugar, macros,
    strformat, strutils, os,
  ]
import godotapi/spatial
import core, models/[states, bots, colors, things, voxels]

# Re-export from voxels
export
  encode_chunk, decode_chunk, encode_delta, decode_delta, pack_voxel,
  unpack_voxel, linear_position, from_linear, is_empty, flush_dirty_chunks,
  flush_dirty_edits, chunk_id_for_pos
export things

include "build_code_template.nim.nimf"

const default_color = ACTION_COLORS[BLUE]

const
  AUTO* = float.high
    ## The default build speed. Must match `auto` in the VM's `enu/types`
    ## (both `float.high`) so a script's `speed = auto` round-trips to the
    ## same value the host tests here.
  AUTO_RAMP_SECONDS = 3.0
    ## How long the auto ramp takes to reach full speed before handing off
    ## to ASAP.
  AUTO_RAMP_START_SPEED = 1.0
  AUTO_RAMP_END_SPEED = 50.0

var
  current_build* {.threadvar.}: Build
  previous_build* {.threadvar.}: Build
  last_placement_time* {.threadvar.}: MonoTime
  dont_join*: bool

const GROUND_ID* = "ground"

const STROKE_DWELL_MS = 500
  ## Holding the aim on a target the current stroke can't touch for this
  ## long re-anchors the stroke there, as if clicking fresh — how a held
  ## button steps to a new plane or unit.

type
  StrokeMode* = enum
    STROKE_PLACE
    STROKE_REMOVE

  Stroke* = object
    ## Hold-and-drag voxel painting. The initial click anchors the stroke
    ## to one unit and one cell plane; while the button stays held, only
    ## cells on that plane get painted. Everything else is inert until the
    ## dwell timer re-anchors or the button is released.
    mode*: StrokeMode
    unit_id*: string
    axis*: int
    plane*: float
    face*: float
      ## The aimed face's coordinate along `axis` at anchor. Removal
      ## continues only while the ray is on this same face plane; anything
      ## looser lets a grazing ray trench through a layer side face by side
      ## face while the cursor sits still.
    painted*: HashSet[Vector3]
      ## Cells this stroke placed. Placement accepts any face whose outside
      ## cell is on the plane — aiming angles often hide the anchor plane —
      ## except faces of these blocks: the ray landing on a just-placed
      ## block is self-induced, not cursor intent.
    last_cell*: Option[Vector3]
      ## The previously painted cell; the next paint interpolates from
      ## here. Cleared (without ending the stroke) whenever the ray leaves
      ## the plane, so interpolation never bridges cells the cursor didn't
      ## actually sweep.
    dwell_unit*: string
    dwell_target*: Vector3
    dwell_since*: MonoTime

var stroke* {.threadvar.}: Stroke

proc active*(self: Stroke): bool =
  self.unit_id != ""

proc end_stroke*() =
  stroke = Stroke()

proc stroke_miss*(id = "", target = vec3()): bool =
  ## The aimed target isn't paintable by the current stroke: break the
  ## interpolation chain and charge the dwell timer toward re-anchoring
  ## there (true once the aim has stayed put for the dwell time). With no
  ## arguments, just break and reset.
  stroke.last_cell = none(Vector3)
  if id == "" or (stroke.dwell_unit, stroke.dwell_target) != (id, target):
    stroke.dwell_unit = id
    stroke.dwell_target = target
    stroke.dwell_since = get_mono_time()
  elif (get_mono_time() - stroke.dwell_since).in_milliseconds >=
      STROKE_DWELL_MS:
    stroke.dwell_since = get_mono_time()
    result = true

proc axis_of(normal: Vector3): int =
  if normal.x != 0: 0 elif normal.y != 0: 1 else: 2

proc anchor_stroke*(
    mode: StrokeMode, unit_id: string, cell, normal, face_point: Vector3
) =
  if not normal.is_axis_aligned:
    end_stroke()
    return
  let axis = axis_of(normal)
  stroke = Stroke(
    mode: mode,
    unit_id: unit_id,
    axis: axis,
    plane: cell[axis],
    face: face_point[axis],
    last_cell: some(cell),
  )

proc continue_stroke*(
    cell: Vector3, paint: proc(cell: Vector3, endpoint: bool) {.gcsafe.}
): bool =
  ## Paint `cell`, interpolating from the stroke's previous cell, unless it
  ## was the last cell painted.
  if stroke.last_cell == some(cell):
    return
  for mid in plane_cells_between(stroke.last_cell.get(cell), cell, stroke.axis):
    paint(mid, false)
  paint(cell, true)
  stroke.last_cell = some(cell)
  stroke.dwell_unit = ""
  true

proc draw*(self: Build, position: Vector3, voxel: VoxelInfo) {.gcsafe.}
proc place_beside(self: Build, local_cell: Vector3) {.gcsafe.}
proc init_voxels_if_needed*(self: Build, watch_edits = true) {.gcsafe.}
proc watch_edit_rows(self: Build) {.gcsafe.}

# =============================================================================
# Build implementation
# =============================================================================

method code_template*(self: Build, imports: string): string =
  result = build_code_template(
    "../scripts/" & self.script_ctx.script.extractFilename(), imports
  )

proc contains*(self: Build, position: Vector3): bool =
  self.voxels.contains(position)

proc voxel_info*(self: Build, position: Vector3): VoxelInfo =
  self.voxels.voxel_info(position)

proc find_voxel*(self: Build, position: Vector3): Option[VoxelInfo] =
  self.voxels.find_voxel(position)

proc find_first*(things: EdSeq[Thing], positions: open_array[Vector3]): Build =
  for thing in things:
    if thing of Build:
      if LOCK in thing.find_root.global_flags:
        # locked things behave like the ground: placements next to them
        # start (or extend) a separate thing, never join the locked one
        continue
      let thing = Build(thing)
      let offset = vec3().global_from(thing)
      for position in positions:
        var loc = position - offset
        if loc in thing:
          var info = thing.voxels.voxel_info(loc)
          if info.kind != HOLE and info.color != ACTION_COLORS[ERASER]:
            return thing
      let first = thing.things.find_first(positions)
      if ?first:
        return first

proc add_build(self, source: Build) =
  dont_join = true
  for pos, info in source.voxels.all_voxels:
    var position = pos.global_from(source)
    position = position.local_to(self)
    self.draw(position, info)

  if source.parent.is_nil:
    state.things -= source
  else:
    source.parent.things -= source
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

    if LOCK in partner.global_flags:
      return

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

proc empty_bounds*(): AABB {.inline.} =
  ## The "no chunks yet" sentinel. Its size is negative, so it can't be fed
  ## to merge/expand — every grower has to seed from it explicitly.
  init_aabb(vec3(), vec3(-1, -1, -1))

proc expand_bounds_to_chunk*(self: Build, chunk_id: Vector3) =
  ## Grow the bounds to cover `chunk_id`. The terrain clips loading and
  ## meshing to these bounds, so every chunk the store holds has to end up
  ## inside them — this is unconditional and idempotent, and there is no
  ## path that can skip it.
  ##
  ## It deliberately does not test containment first: AABB.contains in
  ## godot-nim compares point.z against position.x, so the guard it used to
  ## have dropped legitimate expansions and left units clipped.
  ## `expand` rather than `merge`: merge is a GDNative call, so it is
  ## unavailable to unit tests (and an FFI hop per chunk); expand is pure Nim.
  let range = chunk_id * ChunkSize
  let low = range - ChunkSize - vec3(1, 1, 1)
  let high = range + ChunkSize
  self.bounds =
    if self.bounds == empty_bounds():
      init_aabb(low, high - low)
    else:
      self.bounds.expand(low).expand(high)

proc track_chunk_bounds*(self: Build) =
  ## Every store this build owns reports its chunks here, so bounds growth
  ## has one definition rather than one per construction path.
  let build = self
  self.voxels.on_chunk_created = proc(chunk_id: Vector3) =
    build.expand_bounds_to_chunk(chunk_id)

proc reset_bounds*(self: Build) =
  ## Bounds cover every frame: the terrain clips loading and meshing to them,
  ## so a frame outside them would never show.
  self.bounds = empty_bounds()
  for id in self.frame_order.ids:
    for chunk_id in self.voxels.frame_chunk_ids(id):
      self.expand_bounds_to_chunk(chunk_id)

proc begin_asap*(self: Build) {.gcsafe.} =
  if ASAP_MODE notin self.global_flags:
    debug "ASAP mode BEGIN", build_id = self.id
  self.global_flags += ASAP_MODE

proc end_asap*(self: Build) {.gcsafe.} =
  if ASAP_MODE in self.global_flags:
    debug "ASAP mode END", build_id = self.id
    # flush before bounds: reset_bounds reads the chunk tables, which only
    # reflect this run's drawing once the dirty chunks are flushed
    self.voxels.flush_dirty_chunks()
    self.reset_bounds()
    self.global_flags -= ASAP_MODE

proc arm_auto_ramp*(self: Build) {.gcsafe.} =
  ## Start a fresh `speed = auto` ramp: leave ASAP so blocks appear as they're
  ## drawn, and begin at the slow end. The clock starts on the first drawn
  ## block (`on_begin_move`), the rate climbs each frame (`update_auto_ramp`),
  ## and after `AUTO_RAMP_SECONDS` it hands the rest to ASAP.
  self.auto_ramp_active = true
  self.auto_ramp_started = false
  self.auto_ramp_done = false
  self.voxels_per_frame = AUTO_RAMP_START_SPEED
  self.voxels_remaining_this_frame = 0
  self.end_asap()

proc update_auto_ramp*(self: Build) {.gcsafe.} =
  ## Advance the auto ramp one frame: set the per-frame voxel budget from an
  ## ease-in curve (slow at first) between the start and end speeds, then flip
  ## to ASAP once the ramp's time is up. A no-op unless a ramp is running and
  ## the first block has anchored the clock.
  if not (self.auto_ramp_active and self.auto_ramp_started):
    return
  let elapsed =
    (get_mono_time() - self.auto_ramp_start).in_microseconds.float / 1_000_000.0
  if elapsed >= AUTO_RAMP_SECONDS:
    self.auto_ramp_active = false
    self.auto_ramp_done = true
    self.begin_asap()
    self.voxels_per_frame = float.high
  else:
    let t = elapsed / AUTO_RAMP_SECONDS
    self.voxels_per_frame =
      AUTO_RAMP_START_SPEED + (AUTO_RAMP_END_SPEED - AUTO_RAMP_START_SPEED) * t * t

template buffer*(self: Build, body: untyped) =
  ## Batch many draws into a single flush. `draw` normally syncs each voxel,
  ## which is costly for large procedural builds; inside `buffer:` the draws
  ## accumulate locally (ASAP mode) and flush once — chunks and PERSISTED edits —
  ## when the block exits (even on exception). Suspends `immediate` for the
  ## duration so the draws actually batch, then restores it.
  let was_immediate = self.voxels.immediate
  self.voxels.immediate = false
  self.begin_asap()
  try:
    body
  finally:
    self.end_asap()
    self.voxels.flush_dirty_edits()
    self.voxels.immediate = was_immediate

# A hole is marked (given the color it hides) when a computed block lands in
# it. Each run starts with every hole unmarked; when a run finishes, the holes
# still unmarked no longer cut into anything and are dropped. A run that fails
# never finishes, so it can't drop them. Each frame has its own holes.

proc unmark_holes(self: Build) =
  var marked: seq[Vector3]
  self.voxels.for_hole_edits:
    if info.kind == HOLE and info.color != ACTION_COLORS[ERASER]:
      marked.add pos
  for pos in marked:
    self.voxels.set_edit(pos, (HOLE, ACTION_COLORS[ERASER]))

method collect_garbage*(self: Build) =
  for id in self.frame_order.ids:
    self.voxels.with_frame(id):
      var stale: seq[Vector3]
      self.voxels.for_hole_edits:
        if info.kind == HOLE and info.color == ACTION_COLORS[ERASER]:
          stale.add pos
      for pos in stale:
        self.voxels.del_edit(pos)
      if stale.len > 0:
        self.global_flags += DIRTY

# Frames. Every voxel row is keyed by frame id, and `frame_order` lists the
# ids by index, so switching frames copies nothing and inserting or deleting
# one only rewrites the order. A script run redraws every frame: it starts by
# dropping their computed blocks and going to frame 0. Only manual blocks are
# saved.

proc frames_len*(self: Build): int =
  self.frame_order.ids.len

proc frame_id*(self: Build, index: int): int =
  self.frame_order.ids[index]

proc target_frame*(self: Build) =
  ## Point the store at `frame`: where the script's draws go.
  self.voxels.frame_id = self.frame_id(self.frame)

proc target_shown_frame*(self: Build) =
  ## Point the store at `current_frame`: the display side's reads and hand
  ## edits go to the frame on screen.
  if self.current_frame in 0 ..< self.frames_len:
    self.voxels.frame_id = self.frame_id(self.current_frame)

proc follow_frame(self: Build) =
  ## While nothing plays, the screen shows the frame the script draws into.
  if self.frames_fps <= 0 and self.current_frame != self.frame:
    self.current_frame = self.frame

proc check_not_baking(self: Build, action: string) =
  ## Restructuring frames moves or wipes whole frames, manual blocks
  ## included, which a `bake` can't record or replay.
  if self.baking.len > 0:
    raise ValueError.init(
      "can't " & action & " inside a `bake`: do it before the `bake` block"
    )

proc check_frame_index(self: Build, index: int, grow = false) =
  let limit = if grow: MAX_FRAMES else: self.frames_len
  if index < 0 or index >= limit:
    raise ValueError.init(
      "no frame " & $index & ": frames go from 0 to " & $(limit - 1)
    )

proc new_frame_id(self: Build): int =
  result = self.next_frame_id
  inc self.next_frame_id

proc grow_frames(self: Build, index: int) =
  if index < self.frames_len:
    return
  var order = self.frame_order
  while order.ids.len <= index:
    order.ids.add self.new_frame_id
  self.frame_order = order

proc refresh_edits(self: Build) =
  # hand edits made on main reach this side through the synced edit tables
  self.voxels.flush_dirty_edits()
  self.voxels.rebuild_local_edits()

proc frames_changed(self: Build) =
  self.global_flags += DIRTY

proc frames_hash*(self: Build): Hash =
  ## Every frame's manual blocks, by index. Order-independent across the
  ## table's rows.
  var index: Table[int, int]
  for i, id in self.frame_order.ids:
    index[id] = i
  var sum = cast[uint](hash(self.frames_len))
  for key, packed in self.voxels.edit_snapshots.value:
    if key.id == self.id and key.frame in index:
      sum += cast[uint](hash((index[key.frame], key.loc, packed.data)))
  for key, deltas in self.voxels.edit_deltas.value:
    if key.id == self.id and key.frame in index and ?deltas:
      for delta in deltas:
        sum += cast[uint](hash((index[key.frame], key.loc, delta.data)))
  cast[Hash](sum)

proc go_to_frame*(self: Build, index: int) =
  ## Make `index` the frame the script draws into, growing the frames with
  ## empty ones if it's past the end.
  self.check_frame_index(index, grow = true)
  if index >= self.frames_len:
    self.grow_frames(index)
    self.frames_changed()
  self.frame = index
  self.target_frame()
  self.follow_frame()

proc copy_frame*(self: Build, src: int, dst: int) =
  ## Frame `dst` becomes a copy of frame `src`, growing the frames if `dst`
  ## is past the end.
  self.check_not_baking("copy a frame")
  self.check_frame_index(src)
  self.check_frame_index(dst, grow = true)
  self.refresh_edits()
  self.grow_frames(dst)
  self.voxels.copy_frame(self.frame_id(src), self.frame_id(dst))
  self.frames_changed()

proc insert_frame*(self: Build, src: int, index: int) =
  ## Insert a copy of frame `src` at `index`; later frames move up one.
  self.check_not_baking("insert a frame")
  self.check_frame_index(src)
  if index < 0 or index > self.frames_len:
    raise ValueError.init(
      "can't insert a frame at " & $index & ": frames go from 0 to " &
        $(self.frames_len - 1)
    )
  if self.frames_len >= MAX_FRAMES:
    raise ResourceLimitError.init(
      "frame limit reached (" & $MAX_FRAMES & ")"
    )
  self.refresh_edits()
  let id = self.new_frame_id
  self.voxels.copy_frame(self.frame_id(src), id)
  var order = self.frame_order
  order.ids.insert(id, index)
  self.frame_order = order
  if self.frame >= index:
    self.frame = self.frame + 1
  if self.current_frame >= index:
    self.current_frame = self.current_frame + 1
  self.frames_changed()

proc after_delete(index, first, last, len: int): int =
  if index > last: index - (last - first + 1)
  elif index >= first: min(first, len - 1)
  else: index

proc delete_frames*(self: Build, first: int, last: int) =
  ## Remove frames `first` to `last`; later frames move down. Removing the
  ## current frame makes the frame that takes its place current. A build
  ## always keeps one frame, so deleting them all leaves an empty one.
  self.check_not_baking("delete frames")
  self.check_frame_index(first)
  self.check_frame_index(last)
  if last < first:
    return
  var order = self.frame_order
  for index in first .. last:
    self.voxels.drop_frame(order.ids[index])
  order.ids.delete(first .. last)
  if order.ids.len == 0:
    order.ids.add self.new_frame_id
  self.frame_order = order
  let len = order.ids.len
  self.frame = self.frame.after_delete(first, last, len)
  self.current_frame = self.current_frame.after_delete(first, last, len)
  self.target_frame()
  self.frames_changed()

proc clear_frame*(self: Build, index: int) =
  ## Empty a frame: its computed and manual blocks are gone. Other frames
  ## keep their indexes.
  self.check_not_baking("clear a frame")
  self.check_frame_index(index)
  self.voxels.drop_frame(self.frame_id(index))
  self.frames_changed()

proc clear_frames*(self: Build) =
  ## Drop every frame but the current one, which becomes frame 0.
  self.check_not_baking("clear frames")
  let keep = self.frame_id(self.frame)
  for id in self.frame_order.ids:
    if id != keep:
      self.voxels.drop_frame(id)
  self.frame_order = FrameOrder(ids: @[keep])
  self.frame = 0
  self.current_frame = 0
  self.frames_changed()

proc paste_frame*(self: Build, src: int, dst: int) =
  ## Lay frame `src`'s blocks over frame `dst`'s; `src` wins where both
  ## have one.
  self.check_not_baking("paste a frame")
  self.check_frame_index(src)
  self.check_frame_index(dst)
  self.refresh_edits()
  self.voxels.paste_frame(self.frame_id(src), self.frame_id(dst))
  self.frames_changed()

proc play*(
    self: Build, fps: float = 8.0, loop: bool = true, first = 0, last = -1
) =
  ## Start playing frames `first` to `last` (the last frame by default); the
  ## server advances `current_frame` at `fps`. The script keeps drawing into
  ## `frame`.
  let last = if last < 0: self.frames_len - 1 else: last
  self.check_frame_index(first)
  self.check_frame_index(last)
  if last < first:
    raise ValueError.init(
      "no frames to play from " & $first & " to " & $last
    )
  self.voxels.flush_dirty_chunks()
  self.global_flags += DIRTY
  self.frames_first = first
  self.frames_last = last
  self.frames_loop = loop
  if self.current_frame notin first .. last:
    self.current_frame = first
  self.frames_fps = fps

proc stop*(self: Build) =
  ## Stop playback; the screen stays on the frame it was showing.
  self.global_flags += DIRTY
  self.frames_fps = 0.0

proc add_voxel*(self: Build, position: Vector3, voxel: VoxelInfo) =
  self.voxels.add_voxel(position, voxel)

proc del_voxel(self: Build, position: Vector3) =
  self.voxels.del_voxel(position)

proc restore_edits*(self: Build) =
  if self.voxels.adopt_edit_chunks():
    return
  self.voxels.for_all_edits:
    assert info.kind in {PERSISTED, HOLE}
    if info.kind != HOLE:
      self.add_voxel(pos, info)
    else:
      if pos in self.voxels:
        var edit = info
        edit.color = self.voxels.voxel_info(pos).color
        self.voxels.set_edit(pos, edit)
        self.voxels.del_voxel(pos)

proc start_frames_run(self: Build, scripted: bool) =
  ## A script run starts on frame 0 and drops every other frame's computed
  ## blocks; reset() does frame 0's.
  if not scripted or self.frames_len <= 1:
    return
  self.refresh_edits()
  self.frame = 0
  self.target_frame()
  for index in 1 ..< self.frames_len:
    self.voxels.with_frame(self.frame_id(index)):
      if self.voxels.restore_needed:
        self.voxels.clear()
        self.restore_edits()
      self.unmark_holes()

proc record_bake(self: Build, position: Vector3, color: Color) =
  ## A computed block landed while `bake` bodies run: each of them records it
  ## relative to the pose and frame it started on.
  let packed = pack_voxel(pack_color_index(self.shared, color), TRANSIENT.ord)
  for capture in self.baking.mitems:
    let local = capture.start.xform_inv_vector3(position)
    let cell = vec3(local.x.round, local.y.round, local.z.round)
    capture.cells
      .mget_or_put(
        self.frame - capture.start_frame,
        Table[Vector3, array[CHUNK_VOLUME, PackedVoxel]].init,
      )
      .mget_or_put(chunk_id_for_pos(cell), default(array[CHUNK_VOLUME, PackedVoxel]))[
        linear_position(local_pos_in_chunk(cell))
      ] = packed

proc draw*(self: Build, position: Vector3, voxel: VoxelInfo) {.gcsafe.} =
  if voxel.kind == TRANSIENT and self.baking.len > 0:
    self.record_bake(position, voxel.color)
  if voxel.kind == TRANSIENT:
    if self.voxels.has_edit(position):
      var edit = self.voxels.get_edit(position)
      if edit.kind == HOLE:
        # We're using color as a flag to indicate that the hole is active
        edit.color = voxel.color
        self.voxels.set_edit(position, edit)
        return
      elif edit.kind == PERSISTED and edit.color == voxel.color:
        # the script now draws what the edit added: it's computed from here on
        self.voxels.del_edit(position)
        self.add_voxel(position, voxel)
        self.global_flags += DIRTY
    elif ?self.clone_of and Build(self.clone_of).voxels.has_edit(position) and
        Build(self.clone_of).voxels.get_edit(position).kind == HOLE:
      return
    else:
      self.add_voxel(position, voxel)
  else:
    self.global_flags += DIRTY
    if ?self.shared:
      var voxel = voxel
      if voxel.kind == HOLE and position in self:
        voxel.color = self.voxel_info(position).color
      self.voxels.set_edit(position, voxel)
      if voxel.kind != HOLE:
        self.add_voxel(position, voxel)
      else:
        self.del_voxel(position)

  if position == vec3(0, 0, 0) and voxel.kind != TRANSIENT:
    self.start_color = voxel.color

  if not dont_join and voxel.kind == PERSISTED:
    self.maybe_join_previous_build(position, voxel)

proc sync_turtle*(self: Build) =
  # Mirror draw_transform for the render side. Called once per batch of
  # draw_transform writes, not per voxel — see turtle_transform in types.nim.
  if self.turtle_transform != self.draw_transform:
    self.turtle_transform = self.draw_transform

proc drop_block(self: Build) =
  if self.drawing:
    var p = self.draw_transform.origin.snapped(vec3(1, 1, 1))
    self.draw(p, (TRANSIENT, self.color))

proc has_visible_voxels(self: Build): bool =
  for pos, info in self.voxels.all_voxels:
    if info.color != ACTION_COLORS[ERASER]:
      return true
  false

const BLOCK_LOG_CAP = 200

proc log_block_placement(self: Build, local: Vector3, color: Color) =
  if state.player.is_nil:
    return
  let entry: BlockLogEntry = (
    thing_id: self.id,
    color: color,
    local_position: local,
    global_position: local.world_from(self),
    timestamp: get_mono_time(),
  )
  state.player.block_log_entries.add entry
  while state.player.block_log_entries.len > BLOCK_LOG_CAP:
    state.player.block_log_entries.del 0

proc erase_cell(self: Build, cell: Vector3) =
  ## Erasing a computed block leaves a hole, so the script doesn't put it
  ## back. A manual block just goes.
  if self.voxels.has_edit(cell) and self.voxels.get_edit(cell).kind == PERSISTED:
    self.voxels.del_edit(cell)
    self.del_voxel(cell)
    self.global_flags += DIRTY
  else:
    self.draw(cell, (HOLE, ACTION_COLORS[ERASER]))

proc paint_cell(self: Build, cell: Vector3, endpoint = false) =
  ## Paint one cell of the active stroke. Interpolated cells (endpoint =
  ## false) skip cells already in the desired state; the aimed cell always
  ## draws, matching a bare click.
  case stroke.mode
  of STROKE_REMOVE:
    if endpoint or cell in self:
      self.erase_cell(cell)
      self.log_block_placement(cell, ACTION_COLORS[ERASER])
  of STROKE_PLACE:
    if LOCK in self.find_root.global_flags and GOD notin state.player.flags:
      stroke.painted.incl cell
      self.place_beside(cell)
    elif endpoint or cell notin self:
      stroke.painted.incl cell
      self.draw(cell, (PERSISTED, state.player.selected_color))
      self.log_block_placement(cell, state.player.selected_color)

proc remove_if_empty(self: Build) =
  if self.things.len == 0 and not self.has_visible_voxels:
    if self.parent.is_nil:
      state.things -= self
    else:
      self.parent.things -= self

proc remove(self: Build) =
  if LOCK in self.find_root.global_flags and GOD notin state.player.flags:
    return
  if state.player.tool notin {Tools.NONE, CODE_MODE, PLACE_BOT}:
    let cell = (self.target_point - self.target_normal * 0.5).floor
    anchor_stroke(
      STROKE_REMOVE, self.id, cell, self.target_normal, self.target_point
    )
    if stroke.active:
      self.paint_cell(cell, endpoint = true)
      self.remove_if_empty()

proc fire(self: Build) =
  # Full transform, not global_from: on a rotated platform the origin-only sum
  # drops the rotation, so the dropped bot lands blocks from the aim target.
  let global_point = self.target_point.world_from(self)
  let locked =
    LOCK in self.find_root.global_flags and GOD notin state.player.flags
  if state.player.tool notin {DISABLED, Tools.NONE, CODE_MODE, PLACE_BOT}:
    let cell = (self.target_point + (self.target_normal * 0.5)).floor
    anchor_stroke(
      STROKE_PLACE, self.id, cell, self.target_normal, self.target_point
    )
    if stroke.active:
      self.paint_cell(cell, endpoint = true)
  elif state.player.tool == PLACE_BOT and BLOCK_TARGET_VISIBLE in state.local_flags and
      state.bot_at(global_point).is_nil:
    let transform = Transform.init(origin = global_point)
    state.things += Bot.init(transform = transform)
  elif state.player.tool == CODE_MODE and not locked:
    let root = self.find_root
    state.player.coding = root

proc stroke_frame*(self: Build) =
  ## Per-frame stroke continuation while a button is held and the ray is on
  ## this build: paint the aimed cell if it's on the stroke's plane,
  ## otherwise charge the dwell timer toward re-anchoring here.
  if state.player.tool in {DISABLED, Tools.NONE, CODE_MODE, PLACE_BOT}:
    return
  if stroke.unit_id == self.id and self.target_normal.is_axis_aligned:
    let inside = (self.target_point - self.target_normal * 0.5).floor
    let (cell, paintable) =
      if stroke.mode == STROKE_REMOVE:
        (inside, self.target_point[stroke.axis] == stroke.face)
      else:
        (
          (self.target_point + self.target_normal * 0.5).floor,
          inside notin stroke.painted,
        )
    if paintable and cell[stroke.axis] == stroke.plane:
      let painted = continue_stroke(
        cell,
        proc(cell: Vector3, endpoint: bool) =
          self.paint_cell(cell, endpoint),
      )
      if painted and stroke.mode == STROKE_REMOVE:
        self.remove_if_empty()
      return
  if stroke_miss(self.id, self.target_point):
    if SECONDARY_DOWN in state.local_flags:
      self.remove
    elif PRIMARY_DOWN in state.local_flags:
      self.fire

proc is_moving(self: Build, move_mode: int): bool =
  move_mode == 2

proc is_setting_anchor(move_mode: int): bool =
  move_mode == 3

method on_begin_move*(
    self: Build, direction: Vector3, steps: float, move_mode: int
): Callback =
  if is_setting_anchor(move_mode):
    let offset = self.anchor_value.basis.xform(direction) * steps
    self.anchor_value.origin = self.anchor_value.origin + offset
    return
  let move = self.is_moving(move_mode)
  if move:
    self.end_asap() # Exit ASAP mode when switching to movement
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
        return DONE
      else:
        self.transform_value.origin =
          self.transform.origin + (moving * self.speed * delta)
        return RUNNING
  else:
    if self.speed == AUTO and self.auto_ramp_active:
      # Anchor the ramp clock to the first drawn block; update_auto_ramp drives
      # voxels_per_frame from here on.
      if not self.auto_ramp_started:
        self.auto_ramp_started = true
        self.auto_ramp_start = get_mono_time()
    elif self.speed == 0 or self.speed == AUTO:
      # ASAP, or auto with no ramp armed (e.g. a level load): draw it all.
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

      self.sync_turtle()
      if count.float >= steps: NEXT_TASK else: RUNNING

method on_begin_turn*(
    self: Build, axis: Vector3, degrees: float, lean: bool, move_mode: int
): Callback =
  let map =
    if lean:
      {LEFT: BACK, RIGHT: FORWARD, BACK: RIGHT, FORWARD: LEFT}.to_table
    else:
      {LEFT: UP, RIGHT: DOWN, UP: RIGHT, DOWN: LEFT}.to_table
  let axis = map[axis]
  if is_setting_anchor(move_mode):
    let world_axis = self.anchor_value.basis.xform(axis)
    self.anchor_value.basis =
      self.anchor_value.basis.rotated(world_axis, deg_to_rad(degrees))
        .orthonormalized
    return
  let move = self.is_moving(move_mode)
  if move:
    self.end_asap()
    self.voxels_per_frame = 0
    var duration = 0.0
    let axis = self.transform.basis.orthonormalized.xform(axis)
    let scale = self.scale
    # Rotate about the anchor pivot, not the transform origin — a build
    # drawn off its origin (e.g. one kept inside a single chunk) would
    # otherwise swing its body around the corner instead of turning in
    # place. With no anchor set, the pivot IS the origin, so this is a
    # no-op for the common case.
    let pivot = self.pivot_local
    let offset = self.anchor.origin
    var final_transform = self.transform
    final_transform.basis = final_transform.basis
      .rotated(axis, deg_to_rad(degrees)).orthonormalized
      .scaled(vec3(scale, scale, scale))
    final_transform.origin = pivot - final_transform.basis.xform(offset)

    result = proc(delta: float, _: MonoTime): TaskStates =
      duration += delta
      let basis = self.transform.basis.rotated(
        axis, deg_to_rad(degrees * delta * self.speed)
      )
      self.transform_value.basis = basis
      self.transform_value.origin = pivot - basis.xform(offset)

      if duration <= 1.0 / self.speed:
        RUNNING
      else:
        self.transform = final_transform
        DONE
  else:
    let axis = self.draw_transform.basis.xform(axis)
    self.draw_transform_value.basis =
      self.draw_transform.basis.rotated(axis, deg_to_rad(degrees))
    self.draw_transform = self.draw_transform.orthonormalized()
    self.sync_turtle()

proc reset_state*(self: Build) =
  self.init_shared
  self.draw_transform = Transform.init
  self.sync_turtle()
  self.transform = self.start_transform

method reset*(self: Build) =
  debug "resetting build", id = self.id
  self.transform = self.start_transform
  self.color = self.start_color
  self.speed = AUTO # ramp up then finish ASAP, unless the script sets a speed
  self.auto_ramp_active = false
  self.auto_ramp_started = false
  self.auto_ramp_done = false
  self.begin_asap()
  self.scale = 1

  self.global_flags += RESETTING
  self.global_flags += VISIBLE
  self.reset_state()
  self.baking.set_len(0)
  self.bake_key_sites.clear

  # A run stops playback and redraws every frame from frame 0. A build with
  # NO script has no rerun to re-establish playback or display — its frames
  # are all it has (e.g. a saved sea), so it stays where it was.
  let scripted =
    ?self.script_ctx and self.script_ctx.script != "" and
    file_exists(self.script_ctx.script)
  if scripted:
    self.frames_fps = 0.0
  self.start_frames_run(scripted)
  self.target_frame()
  self.follow_frame()

  # Rebuild the voxel state only when needed (see restore_needed): a
  # freshly-loaded unit's live state is already exactly its persisted edits,
  # and clearing + restoring would erase and remesh identical content — at
  # load, phase 2 rebuilt the whole sea on screen right after the reveal.
  let rebuild = self.voxels.restore_needed
  if rebuild:
    self.voxels.clear()

  self.things.clear()
  self.global_flags -= RESETTING
  if rebuild:
    self.restore_edits
  self.unmark_holes()
  self.draw(vec3(), (TRANSIENT, self.start_color))

method ensure_visible*(self: Build) =
  if self.things.len == 0 and not self.has_visible_voxels:
    let color =
      if self.start_color == ACTION_COLORS[ERASER]:
        ACTION_COLORS[BLUE]
      else:
        self.start_color
    self.draw(vec3(), (TRANSIENT, color))

method destroy*(self: Build) =
  self.destroy_impl

proc init*(
    _: type Build,
    id = "build_" & generate_id(),
    transform = Transform.init,
    color = default_color,
    clone_of: Thing = nil,
    global = true,
    bot_collisions = true,
    parent: Thing = nil,
): Build =
  # Everything built here is owned by this build's id (containers stamp owner_id
  # = id, riding their CREATE), so destroy_owned(id) tears it all down. init_thing,
  # called within, inherits the scope through the threadvar.
  id.own:
    # The synced voxel tables: real Build Ed fields, generated ids (no derived
    # id, so a reload mints fresh ones — no destroy+recreate-same-id race).
    # EAGER: the worker seeds these before the unit joins the collection, so ed's
    # ordered delivery puts every chunk on main before the build's node is set
    # up — prefill hits and each block meshes with its content the first time (no
    # empty-then-repaint). (Was LAZY: pull-only paging; that left prefill missing
    # on load, so blocks meshed empty and repainted, spiking load and flashing
    # empty at reveal.)
    let packed_chunks = EdTable[FrameChunk, SnapshotData].init(
      flags = {SYNC_LOCAL, SYNC_REMOTE}
    )
    let chunk_deltas = EdTable[FrameChunk, EdSeq[DeltaUpdate]].init(
      flags = {SYNC_LOCAL, SYNC_REMOTE}
    )
    let voxels = VoxelStore.init(thing_id = id)
    var self = Build(
      id: id,
      packed_chunks: packed_chunks,
      chunk_deltas: chunk_deltas,
      current_frame_value: EdValue[int].init(0, flags = {SYNC_LOCAL, SYNC_REMOTE}),
      frame_order_value:
        EdValue[FrameOrder].init(
          FrameOrder(ids: @[0]), flags = {SYNC_LOCAL, SYNC_REMOTE}
        ),
      next_frame_id: 1,
      frames_fps_value: EdValue[float].init(0.0, flags = {SYNC_LOCAL, SYNC_REMOTE}),
      frames_loop_value: EdValue[bool].init(true, flags = {SYNC_LOCAL, SYNC_REMOTE}),
      frames_first_value: EdValue[int].init(0, flags = {SYNC_LOCAL, SYNC_REMOTE}),
      frames_last_value: EdValue[int].init(0, flags = {SYNC_LOCAL, SYNC_REMOTE}),
      sealed_frames_value:
        EdValue[bool].init(true, flags = {SYNC_LOCAL, SYNC_REMOTE}),
      cull_down_faces_value:
        EdValue[bool].init(false, flags = {SYNC_LOCAL, SYNC_REMOTE}),
      voxels: voxels,
      start_transform: transform,
      draw_transform_value: EdValue[Transform].init(Transform.init, flags = {}),
      turtle_transform_value:
        EdValue[Transform].init(Transform.init, flags = {SYNC_LOCAL, SYNC_REMOTE}),
      start_color: color,
      drawing: true,
      bounds_value: ed(empty_bounds()),
      clone_of: clone_of,
      bot_collisions: bot_collisions,
      parent: parent,
    )

    voxels.build = self # back-ref for live table reads (set once self exists)
    self.init_thing

    # Set up edit references after init_thing creates Shared
    self.voxels.edit_snapshots = self.shared.edit_snapshots
    self.voxels.edit_deltas = self.shared.edit_deltas
    self.watch_edit_rows()

    self.track_chunk_bounds()

    if global:
      self.global_flags += GLOBAL
    self.reset()
    result = self

proc init*(_: type Build, x, y, z: float, save = false): Build =
  ## A build at (x, y, z) for demos and external agents. EPHEMERAL by default
  ## (reaped when the session ends); pass `save = true` to persist it with the
  ## level. Draws render as they're made — each `draw` syncs immediately — so a
  ## shell appears block by block; wrap a batch in `build.buffer:` to accumulate
  ## and flush once instead (far faster for large procedural builds).
  result = Build.init(transform = Transform.init(vec3(x, y, z)))
  if not save:
    result.global_flags += EPHEMERAL
  # enu's Build.init starts in ASAP mode (batched meshing — the right default
  # for scripted builds that draw a lot before their first frame). An agent
  # drawing directly wants the opposite: visible as it goes. Leave ASAP and sync
  # each draw. `buffer:` flips both back for the span of a batch.
  result.end_asap()
  result.voxels.immediate = true

proc place_beside(self: Build, local_cell: Vector3) =
  ## Ground-style placement for locked builds: the cell goes to an adjacent
  ## unlocked build (find_first skips locked trees), or starts a new unit —
  ## the locked build itself never changes.
  let point = local_cell.world_from(self).round
  let now = get_mono_time()
  var add_to =
    if ?current_build and (now - last_placement_time).in_milliseconds <= 500:
      current_build
    else:
      state.things.find_first(point.surrounding)
  if ?add_to:
    add_to.draw(point.local_to(add_to), (PERSISTED, state.player.selected_color))
    add_to.log_block_placement(point.local_to(add_to), state.player.selected_color)
  else:
    add_to = Build.init(
      transform = Transform.init(origin = point),
      global = true,
      color = state.player.selected_color,
    )
    # A placed build has no script; render its voxels directly instead of
    # waiting out the ASAP paste batching (see Ground.fire).
    add_to.end_asap()
    state.things += add_to

proc watch_edit_rows(self: Build) =
  ## Edits written elsewhere (main's clicks, other players) make this side's
  ## decoded copy of their chunk stale. A delta added to a row fires only
  ## that row's seq, so each seq is watched too.
  proc changed(key: EditKey) =
    self.voxels.edit_row_changed((key.frame, key.loc))

  proc watch_deltas(key: EditKey, deltas: EdSeq[DeltaUpdate]) =
    deltas.watch:
      changed(key)

  for key, deltas in self.voxels.edit_deltas:
    if key.id == self.id and ?deltas:
      watch_deltas(key, deltas)

  self.voxels.edit_snapshots.watch:
    if change.item.key.id == self.id:
      changed(change.item.key)
  self.voxels.edit_deltas.watch:
    let key = change.item.key
    if key.id == self.id:
      changed(key)
      if added and ?change.item.value:
        watch_deltas(key, change.item.value)

proc init_voxels_if_needed*(self: Build, watch_edits = true) =
  ## Rebuild the local render wrapper if nil (the plain `voxels` field doesn't
  ## ride the closure, so it's nil after a cross-thread sync). The synced tables
  ## are the Build's own Ed fields — reconnected by reference after sync, so we
  ## just wrap them (no id lookup, no aliasing).
  ##
  ## `watch_edits` keeps the worker's decoded edits in step with rows written
  ## elsewhere. Main passes false: it decodes them again each frame.
  self.init_shared()
  if not ?self.shared:
    # Narrow replica whose `shared` (inherited from the parent on a parented
    # thing, or our own synced singleton) hasn't filled yet. sync_ready keeps
    # the join deferred until it's ready, so reaching here means a join slipped
    # past that gate — bail rather than deref nil. A later join pass heals it.
    notice "init_voxels_if_needed: shared not ready, deferring", thing = self.id
    return
  if ?self.voxels and self.voxels.edit_snapshots != self.shared.edit_snapshots:
    # A reload revives this replica in place (same thing id), keeping plain
    # fields — including this wrapper, whose edit-table refs were captured at
    # init and now dangle on the previous generation's destroyed tables (so
    # prefill serves nothing and never heals). packed_chunks survives only
    # because it's read live through `build`. Rebuild against the current
    # shared.
    self.voxels = nil
  if not ?self.voxels:
    self.voxels = VoxelStore.init(
      ctx = Ed.thread_ctx,
      thing_id = self.id,
      build = self,
      edit_snapshots = self.shared.edit_snapshots,
      edit_deltas = self.shared.edit_deltas,
    )
    if watch_edits:
      self.watch_edit_rows()
    self.track_chunk_bounds()

proc setup_packed_chunk_watches(self: Build) =
  ## Set up watches for packed_chunks and chunk_deltas to reconstruct local voxels on clients.
  proc watch_delta_seq(chunk_id: FrameChunk, delta_seq: EdSeq[DeltaUpdate]) =
    delta_seq.watch:
      if added:
        self.voxels.apply_delta(chunk_id, change.item)

  # Process any snapshots that arrived before the watch was set up
  for chunk_id, snapshot in self.voxels.packed_chunks:
    self.voxels.apply_snapshot(chunk_id, snapshot)

  # Process any deltas that arrived before the watch was set up
  for chunk_id, delta_seq in self.voxels.chunk_deltas:
    if ?delta_seq:
      for delta in delta_seq:
        self.voxels.apply_delta(chunk_id, delta)
      watch_delta_seq(chunk_id, delta_seq)

  self.voxels.packed_chunks.watch:
    if added:
      self.voxels.apply_snapshot(change.item.key, change.item.value)
    elif removed and not modified:
      # Paged out (a rewrite is REMOVED+MODIFIED and skipped): drop the
      # chunk's local voxel state. The authority keeps the data; moving back
      # re-requests it.
      self.voxels.unload_chunk(change.item.key)

  self.voxels.chunk_deltas.watch:
    if added:
      let chunk_id = change.item.key
      let delta_seq = change.item.value
      if ?delta_seq:
        for delta in delta_seq:
          self.voxels.apply_delta(chunk_id, delta)
        watch_delta_seq(chunk_id, delta_seq)
    elif removed and not modified:
      if change.item.key notin self.voxels.packed_chunks:
        # Delta-only chunk paged out; no packed_chunks REMOVED will fire.
        self.voxels.unload_chunk(change.item.key)

method worker_thread_joined*(self: Build, worker: Worker) =
  proc_call worker_thread_joined(Thing(self), worker)
  self.init_shared()
  self.init_voxels_if_needed()
  # Only clients need to apply packed chunks received from server
  if SERVER notin state.local_flags:
    self.setup_packed_chunk_watches()
  # A build authored by a remote client (no local script) arrives stuck in
  # ASAP_MODE (Build.init -> reset -> begin_asap): its synced voxels sit
  # buffered and never mesh. A scripted build finishes via end_asap when its
  # code runs, and a reloaded build via the load path — a remote, script-less
  # build gets neither. Do it here: draw the default block to re-kick the
  # build's terrain streaming, then end_asap so the synced chunks mesh
  # directly. Gated to remote-owned, not-loading, script-less builds, so
  # local in-game drawing and scripted builds are untouched.
  elif self.code.owner != state.worker_ctx_name and
      SCRIPT_INITIALIZING notin self.global_flags and
      self.code.nim.strip == "" and
      not (?self.script_ctx and self.script_ctx.script != "" and
        file_exists(self.script_ctx.script)):
    self.draw(vec3(), (TRANSIENT, self.start_color))
    self.end_asap()

method main_thread_joined*(self: Build) =
  proc_call main_thread_joined(Thing(self))
  self.init_voxels_if_needed(watch_edits = false)
  self.setup_packed_chunk_watches()

  self.local_flags.watch:
    if HOVER.added and state.player.tool == CODE_MODE:
      if PLAYING notin state.player.flags and
          TOUCH_CONTROLS notin state.local_flags and (
            LOCK notin self.find_root.global_flags or GOD in state.player.flags
          ):
        let root = self.find_root(true)
        root.walk_tree proc(thing: Thing) =
          thing.local_flags += HIGHLIGHT
    elif HOVER.removed:
      let root = self.find_root(true)
      root.walk_tree proc(thing: Thing) =
        thing.local_flags -= HIGHLIGHT
    if change.item in {TARGET_MOVED, HOVER} and state.player.tool == PLACE_BOT:
      if self.target_normal == UP:
        state.push_flag BLOCK_TARGET_VISIBLE
      else:
        state.pop_flag BLOCK_TARGET_VISIBLE

  state.local_flags.watch:
    if HOVER in self.local_flags and VIEWPORT_FOCUSED in state.local_flags:
      if PRIMARY_DOWN.added:
        self.fire
      elif SECONDARY_DOWN.added:
        self.remove
    if PRIMARY_DOWN.removed or SECONDARY_DOWN.removed:
      end_stroke()

  state.player.flags.watch:
    if PLAYING.added:
      self.local_flags -= HIGHLIGHT
    elif PLAYING.removed:
      if HOVER in self.local_flags:
        self.local_flags += HIGHLIGHT

method on_collision*(self: Build, partner: Model, normal: Vector3) =
  self.collisions.add (partner.id, normal)

method off_collision*(self: Thing, partner: Model) =
  if self.collisions.valid:
    for collision in self.collisions.value.dup:
      if collision.id == partner.id:
        self.collisions -= collision

method clone*(self: Build, clone_to: Thing, id: string): Thing =
  var transform = clone_to.transform
  var global = true
  if clone_to of Build:
    transform = Build(clone_to).draw_transform
    global = false

  let bot_collisions = true
  let clone = Build.init(
    id = id,
    transform = transform,
    clone_of = self,
    global = global,
    color = self.start_color,
    bot_collisions = bot_collisions,
    parent = clone_to,
  )

  # Copy edits from source to clone
  self.voxels.for_all_edits:
    if info.kind != HOLE and not clone.voxels.has_edit(pos):
      clone.add_voxel(pos, info)

  clone.restore_edits
  result = clone

proc voxel_mem_stats*(
    things: EdSeq[Thing]
): tuple[builds, lv_chunks, lv_voxels, packed, edit_chunks, edit_voxels: int] =
  ## Aggregate resident voxel-store sizes across every build in the tree — the
  ## ENU_VOXEL_MEM_LOG counters logged per side (see game.nim / worker.nim).
  var builds, lv_chunks, lv_voxels, packed, edit_chunks, edit_voxels = 0
  things.value.walk_tree proc(thing: Thing) =
    if thing of Build and ?Build(thing).voxels:
      let v = Build(thing).voxels
      inc builds
      # lv_* now counts the decoded chunk cache — the resident working set
      # that replaced local_voxels (same meaning: decoded voxels held in
      # memory on this side).
      lv_chunks += v.chunk_cache.len
      for chunk in v.chunk_cache.values:
        lv_voxels += chunk.count
      packed += v.packed_chunks.value.len
      edit_chunks += v.local_edits.len
      for chunk in v.local_edits.values:
        edit_voxels += chunk.len
  (builds, lv_chunks, lv_voxels, packed, edit_chunks, edit_voxels)

when is_main_module:
  import unittest, states
  type Node = ref object of RootObj

  var b = Build.init

  b.draw vec3(1, 1, 1), (TRANSIENT, Color())
  assert vec3(1, 1, 1) in b.voxels
  b.draw vec3(17, 17, 17), (TRANSIENT, Color())
  assert vec3(17, 17, 17) in b.voxels
  var c = Build.init(transform = Transform(origin: vec3(5, 5, 5)))
  c.parent = b

  c.draw vec3(14, 14, 14), (PERSISTED, Color())
  c.local_flags += HOVER
