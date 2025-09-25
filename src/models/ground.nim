import gdext
import gdext/classes/gdnode3d
import core, states, bots, builds

var add_to {.threadvar.}: Build
proc fire(self: Ground, append = false) {.gcsafe.} =
  state.draw_unit_id = "ground"
  let point = (self.target_point - vector3(0.5, 0, 0.5)).trunc
  print("[GROUND] fire called - tool: " & $state.current_tool & ", target: " & $self.target_point)
  if state.current_tool notin {Disabled, CodeMode, PlaceBot}:
    if not append:
      add_to = state.units.find_first(point.surrounding)
    if ?add_to:
      let local = point.local_to(add_to)
      add_to.draw(local, (Manual, state.selected_color))
    else:
      add_to = Build.init(
        transform = Transform3D.init(origin = point),
        global = true,
        color = state.selected_color,
      )

      state.units += add_to
  elif state.current_tool == PlaceBot and state.bot_at(self.target_point).is_nil:
    print("[GROUND] Placing bot at: " & $self.target_point)
    var t = Transform3D.init(origin = self.target_point)
    let bot = Bot.init(transform = t)
    print("[GROUND] Bot created with id: " & bot.id)
    state.units += bot
    print("[GROUND] Bot added to state.units")

proc init*(_: type Ground, node: Node3D): Ground =
  let self = Ground(
    global_flags: ~set[GlobalModelFlags],
    local_flags: ~(set[LocalModelFlags], {SyncLocal}),
  )

  state.local_flags.changes:
    if PrimaryDown.added and Hover in self.local_flags:
      print("[GROUND] PrimaryDown with Hover - firing")
      self.fire(append = false)
    elif PrimaryDown.added:
      print("[GROUND] PrimaryDown but NO Hover flag")
    if PrimaryDown.removed or SecondaryDown.removed:
      state.draw_unit_id = ""

  self.local_flags.changes:
    if Hover.added:
      print("[GROUND] Hover flag added to ground")
    elif Hover.removed:
      print("[GROUND] Hover flag removed from ground")
    if PrimaryDown in state.local_flags and state.draw_unit_id == "ground":
      if change.item == TargetMoved:
        self.fire(append = true)

  result = self
