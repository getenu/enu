import
  std/[
    tables, sets, options, sequtils, math, wrapnils, monotimes, sugar, deques,
    macros, base64,
  ]
import gdext/math
import core, models/[states, bots, colors, units]
const ChunkSize = vector3(16, 16, 16)

include "build_code_template.nim.nimf"

const default_color = action_colors[Colors.Blue]

var
  current_build* {.threadvar.}: Build
  previous_build* {.threadvar.}: Build
  dont_join*: bool
  skip_point = vector3(0, 0, 0)
  last_point: Vector3
  draw_normal = vector3(0, 0, 0)

proc draw*(self: Build, position: Vector3, voxel: VoxelInfo) {.gcsafe.}

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
  result = buf in self.chunks and position in self.chunks[buf]

proc voxel_info*(self: Build, position: Vector3): VoxelInfo =
  self.chunks[position.buffer][position]

proc find_voxel*(self: Build, position: Vector3): Option[VoxelInfo] =
  let buf = position.buffer
  result =
    if buf in self:
      some(self.chunks[buf][position])
    else:
      none(VoxelInfo)

proc find_first*(units: ZenSeq[Unit], positions: open_array[Vector3]): Build =
  for unit in units:
    if unit of Build:
      let unit = Build(unit)
      let offset = vector3(0, 0, 0).global_from(unit)
      for position in positions:
        var loc = position - offset
        if loc in unit:
          var info = unit.chunks[loc.buffer][loc]
          if info.kind != Hole and info.color != action_colors[Eraser]:
            return unit
      let first = unit.units.find_first(positions)
      if ?first:
        return first

proc add_build(self, source: Build) =
  dont_join = true
  for chunk_id, chunk in source.chunks:
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
  let min = range - ChunkSize - vector3(1, 1, 1)
  let max = range + ChunkSize
  if not self.bounds.has_point(max):
    self.bounds = self.bounds.expand(max)
  if not self.bounds.has_point(min):
    self.bounds = self.bounds.expand(min)

proc reset_bounds*(self: Build) =
  self.bounds = aabb(vector3(0, 0, 0), vector3(-1, -1, -1))

  for chunk_id, chunk in self.chunks:
    self.expand_bounds_to_chunk(chunk_id)

proc add_voxel(self: Build, position: Vector3, voxel: VoxelInfo) =
  let buffer = position.buffer

  if buffer notin self.chunks:
    self.chunks[buffer] = Chunk.init
    self.expand_bounds_to_chunk(buffer)

  if self.batching:
    if position notin self.chunks[buffer] or
        self.chunks[buffer][position] != voxel:
      if buffer notin self.batched_voxels:
        self.batched_voxels[buffer] = init_table[Vector3, VoxelInfo]()
      self.batched_voxels[buffer][position] = voxel
  else:
    self.chunks[buffer][position] = voxel

proc del_voxel(self: Build, position: Vector3) =
  let buffer = position.buffer
  self.chunks[buffer].del position

proc restore_edits*(self: Build) =
  if self.id in self.shared.edits:
    for loc, info in self.shared.edits[self.id]:
      assert info.kind in {Manual, Hole}
      if info.kind != Hole:
        self.add_voxel(loc, info)
      else:
        let buffer = loc.buffer
        if buffer in self.chunks and loc in self.chunks[buffer]:
          var info = info
          info.color = self.chunks[buffer][loc].color
          var locations = self.shared.edits[self.id]
          locations[loc] = info
          self.shared.edits[self.id] = locations
          self.chunks[buffer].del loc

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

  if position == vector3(0, 0, 0) and voxel.kind != Computed:
    self.start_color = voxel.color

  if not dont_join and voxel.kind == Manual:
    self.maybe_join_previous_build(position, voxel)

proc drop_block(self: Build) =
  if self.drawing:
    var p = self.draw_transform.origin.snapped(vector3(1, 1, 1))
    self.draw(p, (Computed, self.color))

proc remove(self: Build) =
  if state.current_tool notin {CodeMode, PlaceBot}:
    state.skip_block_paint = true
    draw_normal = self.target_normal
    let point =
      self.target_point - self.target_normal -
      (self.target_normal.inverse_normalized * 0.5)

    skip_point = vector3(0, 0, 0)
    last_point = self.target_point
    self.draw(point, (Hole, action_colors[Eraser]))

    if self.units.len == 0 and
        not self.chunks.any_it(
          it.value.any_it(it.value.color != action_colors[Eraser])
        ):
      if self.parent.is_nil:
        state.units -= self
      else:
        self.parent.units -= self

proc fire(self: Build) =
  let global_point = self.target_point.global_from(self)
  if state.current_tool notin {Disabled, CodeMode, PlaceBot}:
    state.skip_block_paint = true
    draw_normal = self.target_normal
    let point = (self.target_point + (self.target_normal * 0.5)).floor
    skip_point = self.target_point + self.target_normal
    last_point = self.target_point
    self.draw(point, (Manual, state.selected_color))
  elif state.current_tool == PlaceBot and BlockTargetVisible in state.local_flags and
      state.bot_at(global_point).is_nil:
    let transform = Transform3D.init(origin = global_point)
    state.units += Bot.init(transform = transform)
  elif state.current_tool == CodeMode:
    let root = self.find_root
    state.open_unit = root

proc is_moving(self: Build, move_mode: int): bool =
  move_mode == 2

method batch_changes*(self: Build): bool =
  if not self.batching:
    self.batching = true
    result = true

method apply_changes*(self: Build) =
  if self.batching:
    for buffer, chunk in self.batched_voxels:
      self.chunks[buffer] += chunk
    self.batched_voxels.clear
    self.batching = false

method on_begin_move*(
    self: Build, direction: Vector3, steps: float, move_mode: int
): Callback =
  let move = self.is_moving(move_mode)
  if move:
    let steps = steps.float
    var duration = 0.0
    let
      moving = self.transform.basis * direction / self.scale
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
): Callback {.gcsafe.} =
  let map =
    if lean:
      {
        core.LEFT: core.BACK,
        core.RIGHT: core.FORWARD,
        core.BACK: core.RIGHT,
        core.FORWARD: core.LEFT,
      }.to_table
    else:
      {
        core.LEFT: core.UP,
        core.RIGHT: core.DOWN,
        core.UP: core.RIGHT,
        core.DOWN: core.LEFT,
      }.to_table
  let axis = map[axis]
  let move = self.is_moving(move_mode)
  if move:
    self.voxels_per_frame = 0
    var duration = 0.0
    let axis = self.transform.basis.orthonormalized() * axis
    let scale = self.scale
    var final_transform = self.transform
    final_transform.basis = final_transform.basis
      .rotated(axis, deg_to_rad(degrees))
      .orthonormalized()
      .scaled(vector3(scale, scale, scale))

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
    let axis = self.draw_transform.basis * axis
    self.draw_transform_value.basis =
      self.draw_transform.basis.rotated(axis, deg_to_rad(degrees))

    self.draw_transform = self.draw_transform.orthonormalized()

proc reset_state*(self: Build) =
  self.init_shared
  self.draw_transform = Transform3D.init
  self.transform = self.start_transform

method reset*(self: Build) {.gcsafe.} =
  debug "resetting build", id = self.id
  self.transform = self.start_transform
  self.color = self.start_color
  self.speed = 1
  self.scale = 1

  self.global_flags += Resetting
  self.global_flags += Visible
  self.reset_state()

  let chunks = self.chunks.value
  for chunk_id, chunk in chunks:
    self.chunks.del(chunk_id)
    chunk.destroy

  self.units.clear()
  self.global_flags -= Resetting
  self.restore_edits
  self.draw(vector3(0, 0, 0), (Computed, self.start_color))

method ensure_visible*(self: Build) =
  # It's possible for a build to have no blocks of its own if has children with
  # blocks. However, if the script fails or is changed to remove its children,
  # the unit will still exist but will have no presence in the world, and is
  # therefor impossible to select or modify. In that case we want to draw a
  # single block.
  if self.units.len == 0 and
      not self.chunks.any_it(
        it.value.any_it(it.value.color != action_colors[Eraser])
      ):
    let color =
      if self.start_color == action_colors[Eraser]:
        action_colors[Colors.Blue]
      else:
        self.start_color
    self.draw(vector3(0, 0, 0), (Computed, color))

method destroy*(self: Build) =
  self.destroy_impl

proc init*(
    _: type Build,
    id = "build_" & generate_id(),
    transform = Transform3D.init,
    color = default_color,
    clone_of: Unit = nil,
    global = true,
    bot_collisions = true,
    parent: Unit = nil,
): Build =
  var self = Build(
    id: id,
    chunks: ~(Table[Vector3, Chunk], {SyncLocal, SyncRemote}),
    start_transform: transform,
    draw_transform_value: ~(Transform3D.init, flags = {}),
    start_color: color,
    drawing: true,
    # GD4: fixme
    bounds_value: ~aabb(vector3(0, 0, 0), vector3(-1, -1, -1)),
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

method main_thread_joined*(self: Build) =
  proc_call main_thread_joined(Unit(self))

  self.local_flags.watch:
    if Hover.added and state.current_tool == CodeMode:
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
        length <= 5 and self.target_point != skip_point
      ):
        if SecondaryDown in state.local_flags:
          self.remove
        elif PrimaryDown in state.local_flags:
          self.fire

    if change.item in {TargetMoved, Hover} and state.current_tool == PlaceBot:
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
    if Hover in self.local_flags:
      if PrimaryDown.added:
        state.draw_unit_id = self.id
        self.fire
      elif SecondaryDown.added:
        state.draw_unit_id = self.id
        self.remove
    if PrimaryDown.removed or SecondaryDown.removed:
      state.draw_unit_id = ""
      last_point = vector3(0, 0, 0)
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

method clone*(self: Build, clone_to: Unit, id: string): Unit {.gcsafe.} =
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

  b.draw vector3(1, 1, 1), (Computed, Color())
  assert vector3(1, 1, 1) in b.chunks[vector3(0, 0, 0)]
  b.draw vector3(17, 17, 17), (Computed, Color())
  assert vector3(17, 17, 17) in b.chunks[vector3(1, 1, 1)]
  var c = Build.init(transform = Transform3D(origin: vector3(5, 5, 5)))
  c.parent = b

  c.draw vector3(14, 14, 14), (Manual, Color())
  c.flags += Hover
