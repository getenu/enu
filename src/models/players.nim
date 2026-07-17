import std/[math]
import godotapi/spatial
import core, models/things

proc init*(_: type Player): Player =
  let player_id = \"player-{Ed.thread_ctx.id}"
  player_id.own:
    let self = Player(
      id: player_id,
      rotation_value: ed(0.0),
      boost_value: EdValue[Vector3].init(),
      start_transform: Transform.init(origin = vec3(0, 1, 0)),
      input_direction_value: EdValue[Vector3].init(),
      cursor_position_value: ed((0, 0)),
      block_log_entries: EdSeq[BlockLogEntry].init(flags = {SYNC_LOCAL}),
    )
    self.init_thing(shared = false)
    self.global_flags += GLOBAL
    self.global_flags += EPHEMERAL

    self.own: # callback on external state, scoped to the player's lifetime
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
  for thing in self.things:
    if thing of Sign:
      let thing = Sign(thing)
      return thing.message

proc `open_code=`*(self: Player, code: string) =
  for thing in self.things:
    if thing of Sign:
      let thing = Sign(thing)
      if code == "":
        thing.global_flags -= VISIBLE
      else:
        thing.message = code
        thing.more = code
        thing.global_flags += VISIBLE
      return

method destroy*(self: Player) =
  if self.things.len > 0:
    Sign(self.things[0]).owner = nil
    self.things.clear
