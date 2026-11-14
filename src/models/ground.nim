import godotapi/spatial
import std/[options]
import core, states, bots, builds

proc placement_cell*(self: Ground): Vector3 =
  (self.target_point - vec3(0.5, 0, 0.5)).trunc

proc fire(self: Ground) {.gcsafe.} =
  let point = self.placement_cell
  if state.player.tool notin {DISABLED, Tools.NONE, CODE_MODE, PLACE_BOT}:
    anchor_stroke(STROKE_PLACE, GROUND_ID, point, UP, self.target_point)
    stroke.creating = CREATE_MODE in state.local_flags
    if not stroke.creating:
      stroke.target = join_target(self, point)
    place_at(point)
  elif state.player.tool == PLACE_BOT and state.bot_at(self.target_point).is_nil:
    var t = Transform.init(origin = self.target_point)
    state.things += Bot.init(transform = t)

proc stroke_frame*(self: Ground) =
  ## Per-frame stroke continuation while a button is held and the ray is on
  ## the ground: paint the aimed cell if the stroke is anchored here,
  ## otherwise charge the dwell timer toward re-anchoring.
  if state.player.tool in {DISABLED, Tools.NONE, CODE_MODE, PLACE_BOT}:
    return
  let cell = self.placement_cell
  if stroke.unit_id == GROUND_ID and self.target_point.y == stroke.face and
      cell.y == stroke.plane:
    discard continue_stroke(
      cell,
      proc(cell: Vector3, endpoint: bool) =
        place_at(cell, endpoint),
    )
  elif stroke_miss(GROUND_ID, self.target_point) and
      PRIMARY_DOWN in state.local_flags:
    self.fire()

proc init*(_: type Ground, node: Spatial): Ground =
  let self = Ground(
    global_flags: EdSet[GlobalModelFlags].init(),
    local_flags: EdSet[LocalModelFlags].init(flags = {SYNC_LOCAL}),
  )

  state.local_flags.changes:
    if PRIMARY_DOWN.added and HOVER in self.local_flags:
      self.fire()
    if PRIMARY_DOWN.removed or SECONDARY_DOWN.removed:
      end_stroke()

  result = self
