import godotapi/spatial
import core, states, bots, builds

var add_to {.threadvar.}: Build
proc fire(self: Ground, append = false) {.gcsafe.} =
  state.draw_unit_id = "ground"
  let point = (self.target_point - vec3(0.5, 0, 0.5)).trunc
  if state.tool notin {Disabled, CodeMode, PlaceBot}:
    if not append:
      add_to = state.units.find_first(point.surrounding)
    if ?add_to:
      let local = point.local_to(add_to)
      add_to.draw(local, (Manual, state.selected_color))
    else:
      add_to =
        Build.init(
          transform = Transform.init(origin = point),
          global = true,
          color = state.selected_color,
        )

      state.units += add_to
      add_to.global_flags += Dirty
  elif state.tool == PlaceBot and state.bot_at(self.target_point).is_nil:
    var t = Transform.init(origin = self.target_point)
    var bot = Bot.init(transform = t)
    state.units += bot
    bot.global_flags += Dirty

proc init*(_: type Ground, node: Spatial): Ground =
  let self =
    Ground(
      global_flags: ~set[GlobalModelFlags],
      local_flags: ~(set[LocalModelFlags], {SyncLocal}),
    )

  state.local_flags.changes:
    if PrimaryDown.added and Hover in self.local_flags:
      self.fire(append = false)
    if PrimaryDown.removed or SecondaryDown.removed:
      state.draw_unit_id = ""

  self.local_flags.changes:
    if PrimaryDown in state.local_flags and state.draw_unit_id == "ground":
      if change.item == TargetMoved:
        self.fire(append = true)

  result = self
