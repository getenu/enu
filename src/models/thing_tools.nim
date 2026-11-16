## Picking a thing up with a move, lift or turn tool, and putting it down.

import std/[math]
import core, models/[states, things]

const ANCHOR_REACH = 0.75
  ## How near the aim has to pass an anchor's marker to pick the anchor up.

var
  holding_anchor* {.threadvar.}: bool
    ## The held thing's anchor is being moved, not the thing.
  anchor_to* {.threadvar.}: Transform
    ## Where the held anchor goes if it's put down now, in its thing's space.
  aimed* {.threadvar.}: Thing
    ## The unit a move, lift or turn tool would pick up, if any.

proc marker*(anchor: Transform): Transform =
  ## Where an anchor's arrow shows, in its thing's space: in the middle of
  ## the block at its origin.
  result = anchor
  result.origin = anchor.origin + vec3(0.5, 0.5, 0.5)

proc near_anchor*(marker, eye, look: Vector3): bool =
  ## Whether the aim from `eye` along `look` passes near enough to `marker`
  ## to pick its anchor up.
  let along = (marker - eye).dot(look)
  along > 0 and (marker - eye - look * along).length < ANCHOR_REACH

proc can_hold*(thing: Thing): bool =
  ## Whether the move, lift and turn tools can pick `thing` up: a unit or bot,
  ## not locked, outside Play.
  if thing.is_nil or not (thing of Build or thing of Bot) or
      PLAYING in state.player.flags:
    return false
  let root = thing.find_root(true)
  LOCK notin root.global_flags or GOD in state.player.flags

proc hold*(thing: Thing) =
  ## Pick up `thing`, with everything else in it.
  assert held.is_nil
  held = thing.find_root(true)
  held.walk_tree proc(thing: Thing) =
    thing.global_flags += HELD
  state.resolve_flags

proc hold_anchor*(thing: Thing) =
  ## Pick up `thing`'s anchor, leaving it where it is.
  assert held.is_nil
  held = thing.find_root(true)
  holding_anchor = true
  anchor_to = held.anchor
  state.resolve_flags

proc let_go() =
  if not holding_anchor:
    held.walk_tree proc(thing: Thing) =
      thing.global_flags -= HELD
  held = nil
  holding_anchor = false
  state.resolve_flags

proc put_down*(transform: Transform) =
  ## Put the held thing down at `transform`, in its parent's space; or its
  ## anchor, in its own space.
  if holding_anchor:
    held.anchor_placed = Placement(before: held.anchor, after: transform)
    held.anchor = transform
  else:
    held.placed = Placement(before: held.transform, after: transform)
    held.transform = transform
  let_go()

proc put_back*() =
  ## Put the held thing back where it was.
  if ?held:
    let_go()

proc lifted*(start: Transform, grab, eye, look: Vector3): Option[Transform] =
  ## `start` raised or lowered by whole blocks, to where the aim from `eye`
  ## along `look` crosses an upright plane through `grab` that faces the eye.
  ## None while looking straight up or down, or away from it.
  var facing = vec3(look.x, 0, look.z)
  if facing.length < 0.01:
    return
  facing = facing.normalized
  let distance = (grab - eye).dot(facing) / look.dot(facing)
  if distance <= 0:
    return
  let hit = eye + look * distance
  var to = start
  to.origin.y += round(hit.y - grab.y)
  some(to)

proc yaw(direction: Vector3): float =
  ## How far `direction` is turned from FORWARD around UP.
  arctan2(-direction.x, -direction.z)

proc tidy*(basis: Basis): Basis =
  ## `basis` with rounding error taken off its whole numbers, so quarter turns
  ## stay exact.
  result = basis
  for row in 0 .. 2:
    for col in 0 .. 2:
      let value = result[row][col]
      if abs(value - round(value)) < 0.0001:
        result[row][col] = round(value)

proc turned*(start, anchor: Transform, eye, look: Vector3): Option[Transform] =
  ## `start` turned around its anchor, so its forward points along whichever
  ## world axis is nearest the way from the anchor to where the aim from
  ## `eye` along `look` crosses the anchor's height. None while that's too
  ## close to the anchor to tell.
  let pivot = start.basis.xform(anchor.origin) + start.origin
  let ahead = vec3(look.x, 0, look.z)
  let aim =
    if abs(look.y) > 0.001 and (pivot.y - eye.y) / look.y > 0:
      eye + look * ((pivot.y - eye.y) / look.y)
    else:
      eye + ahead * 1000
  let want = vec3(aim.x - pivot.x, 0, aim.z - pivot.z)
  if want.length < 0.5:
    return
  let quarter = PI / 2
  let forward = start.basis.xform(anchor.basis.xform(FORWARD))
  let turn =
    round(want.yaw / quarter) * quarter - vec3(forward.x, 0, forward.z).yaw
  var to = start
  to.basis = start.basis.rotated(UP, turn).tidy
  to.origin = pivot - to.basis.xform(anchor.origin)
  some(to)
