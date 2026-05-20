import std/[math]
import godotapi/spatial
import core, models/units

proc init*(_: type Player): Player =
  let self = Player(
    id: \"player-{Ed.thread_ctx.id}",
    rotation_value: ed(0.0),
    start_transform: Transform.init(origin = vec3(0, 1, 0)),
    input_direction_value: EdValue[Vector3].init(),
    cursor_position_value: ed((0, 0)),
    block_log_entries: EdSeq[BlockLogEntry].init(flags = {SYNC_LOCAL}),
  )
  self.init_unit(shared = false)
  self.global_flags += GLOBAL

  state.local_flags.changes:
    if RESETTING_VM.added:
      self.frame_created = state.frame_count
  result = self

method on_begin_turn*(
    self: Player, direction: Vector3, degrees: float, lean: bool, move_mode: int
): Callback =
  let rotation = floor_mod(self.rotation, 360)
  let degrees =
    if direction == LEFT:
      -degrees
    else:
      degrees
  self.rotation_value.touch rotation - degrees
  self.transform = Transform.init(origin = self.transform.origin)

method collect_garbage*(self: Player) =
  discard

proc open_code*(self: Player): string =
  for unit in self.units:
    if unit of Sign:
      let unit = Sign(unit)
      return unit.message

proc `open_code=`*(self: Player, code: string) =
  for unit in self.units:
    if unit of Sign:
      let unit = Sign(unit)
      if code == "":
        unit.global_flags -= VISIBLE
      else:
        unit.message = code
        unit.more = code
        unit.global_flags += VISIBLE
      return

method destroy*(self: Player) =
  if self.units.len > 0:
    Sign(self.units[0]).owner = nil
    self.units.clear
