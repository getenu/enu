import godotapi/spatial
import std/[monotimes, times]
import core, states, bots, builds

var add_to {.threadvar.}: Build
proc fire(self: Ground, append = false) {.gcsafe.} =
  state.draw_unit_id = "ground"
  let point = (self.target_point - vec3(0.5, 0, 0.5)).trunc
  if state.tool notin {DISABLED, CODE_MODE, PLACE_BOT}:
    if not append:
      # Check if we should stick to the last modified build (within 500ms)
      let now = get_mono_time()
      let time_since_last = (now - last_placement_time).in_milliseconds
      if ?current_build and time_since_last <= 500:
        add_to = current_build
      else:
        add_to = state.units.find_first(point.surrounding)
    if ?add_to:
      let local = point.local_to(add_to)
      add_to.draw(local, (MANUAL, state.selected_color))
    else:
      add_to = Build.init(
        transform = Transform.init(origin = point),
        global = true,
        color = state.selected_color,
      )

      state.units += add_to
  elif state.tool == PLACE_BOT and state.bot_at(self.target_point).is_nil:
    var t = Transform.init(origin = self.target_point)
    state.units += Bot.init(transform = t)

proc init*(_: type Ground, node: Spatial): Ground =
  let self = Ground(
    global_flags: EdSet[GlobalModelFlags].init(),
    local_flags: EdSet[LocalModelFlags].init(flags = {SYNC_LOCAL}),
  )

  state.local_flags.changes:
    if PRIMARY_DOWN.added and HOVER in self.local_flags:
      dont_join = true
      self.fire(append = false)
    if PRIMARY_DOWN.removed or SECONDARY_DOWN.removed:
      dont_join = false
      state.draw_unit_id = ""

  self.local_flags.changes:
    if PRIMARY_DOWN in state.local_flags and state.draw_unit_id == "ground":
      if change.item == TARGET_MOVED and state.tool != PLACE_BOT:
        self.fire(append = true)

  result = self
