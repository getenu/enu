import
  std/[
    tables, sets, options, sequtils, math, monotimes, sugar, macros, strformat,
    strutils, os,
  ]
import godotapi/spatial
import core, models/[states, bots, colors, units, voxels]

# Re-export from voxels
export
  encode_chunk, decode_chunk, encode_delta, decode_delta, pack_voxel,
  unpack_voxel, linear_position, from_linear, is_empty, flush_dirty_chunks,
  flush_dirty_edits, chunk_id_for_pos

include "build_code_template.nim.nimf"

const default_color = ACTION_COLORS[BLUE]

var
  current_build* {.threadvar.}: Build
  previous_build* {.threadvar.}: Build
  last_placement_time* {.threadvar.}: MonoTime
  dont_join*: bool
  skip_point = vec3()
  last_point: Vector3
  draw_normal = vec3()

proc draw*(self: Build, position: Vector3, voxel: VoxelInfo) {.gcsafe.}
proc init_voxels_if_needed*(self: Build) {.gcsafe.}

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

proc find_first*(units: EdSeq[Unit], positions: open_array[Vector3]): Build =
  for unit in units:
    if unit of Build:
      let unit = Build(unit)
      let offset = vec3().global_from(unit)
      for position in positions:
        var loc = position - offset
        if loc in unit:
          var info = unit.voxels.voxel_info(loc)
          if info.kind != HOLE and info.color != ACTION_COLORS[ERASER]:
            return unit
      let first = unit.units.find_first(positions)
      if ?first:
        return first

proc add_build(self, source: Build) =
  dont_join = true
  for pos, info in source.voxels.all_voxels:
    var position = pos.global_from(source)
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

proc expand_bounds_to_chunk*(self: Build, chunk_id: Vector3) =
  let range = chunk_id * ChunkSize
  let min = range - ChunkSize - vec3(1, 1, 1)
  let max = range + ChunkSize
  if max notin self.bounds:
    self.bounds = self.bounds.expand(max)
  if min notin self.bounds:
    self.bounds = self.bounds.expand(min)

proc reset_bounds*(self: Build) =
  self.bounds = init_aabb(vec3(), vec3(-1, -1, -1))

  for chunk_id, chunk in self.voxels.local_voxels:
    self.expand_bounds_to_chunk(chunk_id)

  for chunk_id, _ in self.voxels.packed_chunks:
    self.expand_bounds_to_chunk(chunk_id)

proc begin_asap*(self: Build) {.gcsafe.} =
  if ASAP_MODE notin self.global_flags:
    debug "ASAP mode BEGIN", build_id = self.id
  self.global_flags += ASAP_MODE

proc end_asap*(self: Build) {.gcsafe.} =
  if ASAP_MODE in self.global_flags:
    debug "ASAP mode END", build_id = self.id
    self.reset_bounds()
    self.voxels.flush_dirty_chunks()
    self.global_flags -= ASAP_MODE

proc add_voxel*(self: Build, position: Vector3, voxel: VoxelInfo) =
  self.voxels.add_voxel(position, voxel)

proc del_voxel(self: Build, position: Vector3) =
  self.voxels.del_voxel(position)

proc restore_edits*(self: Build) =
  self.voxels.for_all_edits:
    assert info.kind in {MANUAL, HOLE}
    if info.kind != HOLE:
      self.add_voxel(pos, info)
    else:
      if pos in self.voxels:
        var edit = info
        edit.color = self.voxels.voxel_info(pos).color
        self.voxels.set_edit(pos, edit)
        self.voxels.del_voxel(pos)

proc draw*(self: Build, position: Vector3, voxel: VoxelInfo) {.gcsafe.} =
  if voxel.kind == COMPUTED:
    if self.voxels.has_edit(position):
      var edit = self.voxels.get_edit(position)
      if edit.kind == HOLE:
        # We're using color as a flag to indicate that the hole is active
        edit.color = voxel.color
        self.voxels.set_edit(position, edit)
        return
      elif edit.kind == MANUAL and edit.color == voxel.color:
        self.voxels.del_edit(position)
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

  if position == vec3(0, 0, 0) and voxel.kind != COMPUTED:
    self.start_color = voxel.color

  if not dont_join and voxel.kind == MANUAL:
    self.maybe_join_previous_build(position, voxel)

proc drop_block(self: Build) =
  if self.drawing:
    var p = self.draw_transform.origin.snapped(vec3(1, 1, 1))
    self.draw(p, (COMPUTED, self.color))

proc has_visible_voxels(self: Build): bool =
  for pos, info in self.voxels.all_voxels:
    if info.color != ACTION_COLORS[ERASER]:
      return true
  false

const BLOCK_LOG_CAP = 200

proc log_block_placement(self: Build, local: Vector3, color: Colors) =
  if state.player.is_nil:
    return
  let entry: BlockLogEntry = (
    unit_id: self.id,
    color: color,
    local_position: local,
    global_position: local.global_from(self),
    timestamp: get_mono_time(),
  )
  state.player.block_log_entries.add entry
  while state.player.block_log_entries.len > BLOCK_LOG_CAP:
    state.player.block_log_entries.del 0

proc remove(self: Build) =
  if state.tool notin {CODE_MODE, PLACE_BOT}:
    state.skip_block_paint = true
    draw_normal = self.target_normal
    let point =
      self.target_point - self.target_normal -
      (self.target_normal.inverse_normalized * 0.5)

    skip_point = vec3()
    last_point = self.target_point
    self.draw(point, (HOLE, ACTION_COLORS[ERASER]))
    self.log_block_placement(point, ERASER)

    if self.units.len == 0 and not self.has_visible_voxels:
      if self.parent.is_nil:
        state.units -= self
      else:
        self.parent.units -= self

proc fire(self: Build) =
  let global_point = self.target_point.global_from(self)
  if state.tool notin {DISABLED, CODE_MODE, PLACE_BOT}:
    state.skip_block_paint = true
    draw_normal = self.target_normal
    let point = (self.target_point + (self.target_normal * 0.5)).floor
    skip_point = self.target_point + self.target_normal
    last_point = self.target_point
    self.draw(point, (MANUAL, state.selected_color))
    self.log_block_placement(point, Colors(ord state.tool))
  elif state.tool == PLACE_BOT and BLOCK_TARGET_VISIBLE in state.local_flags and
      state.bot_at(global_point).is_nil:
    let transform = Transform.init(origin = global_point)
    state.units += Bot.init(transform = transform)
  elif state.tool == CODE_MODE:
    let root = self.find_root
    state.open_unit = root

proc is_moving(self: Build, move_mode: int): bool =
  move_mode == 2

method on_begin_move*(
    self: Build, direction: Vector3, steps: float, move_mode: int
): Callback =
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
  let move = self.is_moving(move_mode)
  if move:
    self.end_asap()
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
        RUNNING
      else:
        self.transform = final_transform
        DONE
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

  self.global_flags += RESETTING
  self.global_flags += VISIBLE
  self.reset_state()

  self.voxels.clear()

  self.units.clear()
  self.global_flags -= RESETTING
  self.restore_edits
  self.draw(vec3(), (COMPUTED, self.start_color))

method ensure_visible*(self: Build) =
  if self.units.len == 0 and not self.has_visible_voxels:
    let color =
      if self.start_color == ACTION_COLORS[ERASER]:
        ACTION_COLORS[BLUE]
      else:
        self.start_color
    self.draw(vec3(), (COMPUTED, color))

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
  let voxels = VoxelStore.init(id = voxel_id, unit_id = id)
  var self = Build(
    id: id,
    voxels: voxels,
    start_transform: transform,
    draw_transform_value: EdValue[Transform].init(Transform.init, flags = {}),
    start_color: color,
    drawing: true,
    bounds_value: ed(init_aabb(vec3(), vec3(-1, -1, -1))),
    speed: 1.0,
    clone_of: clone_of,
    bot_collisions: bot_collisions,
    parent: parent,
  )

  self.init_unit

  # Set up edit references after init_unit creates Shared
  self.voxels.edit_snapshots = self.shared.edit_snapshots
  self.voxels.edit_deltas = self.shared.edit_deltas
  self.voxels.rebuild_local_edits()

  # Expand bounds as chunks are created (for early chunk loading)
  let build = self
  self.voxels.on_chunk_created = proc(chunk_id: Vector3) =
    build.expand_bounds_to_chunk(chunk_id)

  if global:
    self.global_flags += GLOBAL
  self.reset()
  result = self

proc init_voxels_if_needed*(self: Build) =
  ## Initialize voxels if nil (happens when Build is synced between threads)
  self.init_shared()
  if not ?self.voxels:
    let voxel_id = self.id & ".voxels"
    let ctx = Ed.thread_ctx
    let packed_id = voxel_id & ".packed_chunks"
    let deltas_id = voxel_id & ".chunk_deltas"
    notice "init_voxels_if_needed",
      build_id = self.id,
      packed_id,
      deltas_id,
      packed_exists = (packed_id in ctx),
      deltas_exists = (deltas_id in ctx)
    if packed_id notin ctx or deltas_id notin ctx:
      notice "voxel EdTables not in context, creating new ones",
        build_id = self.id
      self.voxels = VoxelStore.init(
        id = voxel_id,
        unit_id = self.id,
        ctx = ctx,
        edit_snapshots = self.shared.edit_snapshots,
        edit_deltas = self.shared.edit_deltas,
      )
    else:
      self.voxels = VoxelStore(
        id: voxel_id,
        ctx: ctx,
        unit_id: self.id,
        packed_chunks: EdTable[Vector3, SnapshotData](ctx[packed_id]),
        chunk_deltas: EdTable[Vector3, EdSeq[DeltaUpdate]](ctx[deltas_id]),
        edit_snapshots: self.shared.edit_snapshots,
        edit_deltas: self.shared.edit_deltas,
      )
    self.voxels.rebuild_local_edits()
    # Expand bounds as chunks are created
    let build = self
    self.voxels.on_chunk_created = proc(chunk_id: Vector3) =
      build.expand_bounds_to_chunk(chunk_id)

proc setup_packed_chunk_watches(self: Build) =
  ## Set up watches for packed_chunks and chunk_deltas to reconstruct local voxels on clients.
  proc watch_delta_seq(chunk_id: Vector3, delta_seq: EdSeq[DeltaUpdate]) =
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

  self.voxels.chunk_deltas.watch:
    if added:
      let chunk_id = change.item.key
      let delta_seq = change.item.value
      if ?delta_seq:
        for delta in delta_seq:
          self.voxels.apply_delta(chunk_id, delta)
        watch_delta_seq(chunk_id, delta_seq)

method worker_thread_joined*(self: Build, worker: Worker) =
  proc_call worker_thread_joined(Unit(self), worker)
  self.init_shared()
  self.init_voxels_if_needed()
  # Only clients need to apply packed chunks received from server
  if SERVER notin state.local_flags:
    self.setup_packed_chunk_watches()

method main_thread_joined*(self: Build) =
  proc_call main_thread_joined(Unit(self))
  self.init_voxels_if_needed()
  self.setup_packed_chunk_watches()

  self.local_flags.watch:
    if HOVER.added and state.tool == CODE_MODE:
      if PLAYING notin state.local_flags and
          TOUCH_CONTROLS notin state.local_flags:
        let root = self.find_root(true)
        root.walk_tree proc(unit: Unit) =
          unit.local_flags += HIGHLIGHT
    elif HOVER.removed:
      let root = self.find_root(true)
      root.walk_tree proc(unit: Unit) =
        unit.local_flags -= HIGHLIGHT
    if TARGET_MOVED.touched:
      let length = (
        self.target_point * self.target_normal - last_point * self.target_normal
      ).length

      if state.skip_block_paint:
        state.skip_block_paint = false
      elif (
        state.draw_unit_id == self.id and self.target_normal == draw_normal and
        length <= 5 and self.target_point != skip_point and
        state.tool != PLACE_BOT
      ):
        if SECONDARY_DOWN in state.local_flags:
          self.remove
        elif PRIMARY_DOWN in state.local_flags:
          self.fire

    if change.item in {TARGET_MOVED, HOVER} and state.tool == PLACE_BOT:
      if self.target_normal == UP:
        state.push_flag BLOCK_TARGET_VISIBLE
      else:
        state.pop_flag BLOCK_TARGET_VISIBLE

  state.local_flags.watch:
    if HOVER in self.local_flags and VIEWPORT_FOCUSED in state.local_flags:
      if PRIMARY_DOWN.added:
        state.draw_unit_id = self.id
        self.fire
      elif SECONDARY_DOWN.added:
        state.draw_unit_id = self.id
        self.remove
    if PRIMARY_DOWN.removed or SECONDARY_DOWN.removed:
      state.draw_unit_id = ""
      last_point = vec3()
    if PLAYING.added:
      self.local_flags -= HIGHLIGHT
    elif PLAYING.removed:
      if HOVER in self.local_flags:
        self.local_flags += HIGHLIGHT

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

when is_main_module:
  import unittest, states
  type Node = ref object of RootObj

  var b = Build.init

  b.draw vec3(1, 1, 1), (COMPUTED, Color())
  assert vec3(1, 1, 1) in b.voxels
  b.draw vec3(17, 17, 17), (COMPUTED, Color())
  assert vec3(17, 17, 17) in b.voxels
  var c = Build.init(transform = Transform(origin: vec3(5, 5, 5)))
  c.parent = b

  c.draw vec3(14, 14, 14), (MANUAL, Color())
  c.local_flags += HOVER
