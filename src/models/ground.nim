import godotapi/spatial
import std/[monotimes, times, options]
import core, states, bots, builds

var add_to {.threadvar.}: Build

proc place_cell(self: Ground, cell: Vector3, endpoint = false) {.gcsafe.} =
  if ?add_to:
    let local = cell.local_to(add_to)
    if endpoint or local notin add_to:
      add_to.draw(local, (PERSISTED, state.selected_color))
  else:
    add_to = Build.init(
      transform = Transform.init(origin = cell),
      global = true,
      color = state.selected_color,
    )
    # Builds default to ASAP for script drawing, but its paste batching
    # (2s) would make hand-placed blocks appear late. A placed build has
    # no script; render its voxels directly.
    add_to.end_asap()

    state.things += add_to

proc fire(self: Ground) {.gcsafe.} =
  let point = (self.target_point - vec3(0.5, 0, 0.5)).trunc
  if state.tool notin {DISABLED, Tools.NONE, CODE_MODE, PLACE_BOT}:
    dont_join = true
    # Check if we should stick to the last modified build (within 500ms)
    let now = get_mono_time()
    let time_since_last = (now - last_placement_time).in_milliseconds
    if ?current_build and time_since_last <= 500:
      add_to = current_build
    else:
      add_to = state.things.find_first(point.surrounding)
    anchor_stroke(STROKE_PLACE, GROUND_ID, point, UP, self.target_point)
    self.place_cell(point, endpoint = true)
  elif state.tool == PLACE_BOT and state.bot_at(self.target_point).is_nil:
    var t = Transform.init(origin = self.target_point)
    state.things += Bot.init(transform = t)

proc stroke_frame*(self: Ground) =
  ## Per-frame stroke continuation while a button is held and the ray is on
  ## the ground: paint the aimed cell if the stroke is anchored here,
  ## otherwise charge the dwell timer toward re-anchoring.
  if state.tool in {DISABLED, Tools.NONE, CODE_MODE, PLACE_BOT}:
    return
  let cell = (self.target_point - vec3(0.5, 0, 0.5)).trunc
  if stroke.unit_id == GROUND_ID and self.target_point.y == stroke.face and
      cell.y == stroke.plane:
    discard continue_stroke(
      cell,
      proc(cell: Vector3, endpoint: bool) =
        self.place_cell(cell, endpoint),
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
      dont_join = false
      end_stroke()

  result = self
