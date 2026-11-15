## Picking a thing up with a move, lift or turn tool, and putting it down.

import core, models/[states, things]

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

proc let_go() =
  held.walk_tree proc(thing: Thing) =
    thing.global_flags -= HELD
  held = nil
  state.resolve_flags

proc put_down*(transform: Transform) =
  ## Put the held thing down at `transform`, in its parent's space.
  held.placed = Placement(before: held.transform, after: transform)
  held.transform = transform
  let_go()

proc put_back*() =
  ## Put the held thing back where it was.
  if ?held:
    let_go()
