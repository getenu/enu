import unittest2
import core
import models

# Picking a thing up with a move, lift or turn tool, and putting it down.

proc unit_at(x, y, z: float): Build =
  result = Build.init(transform = Transform.init(origin = vec3(x, y, z)))
  state.things += result

suite "Holding things":
  setup:
    state = GameState.init
    state.player = Player.init(id = "player-me")
    state.player.tool = MOVE_TOOL
    held = nil

  test "units and bots can be picked up":
    check unit_at(0, 0, 0).can_hold
    let bot = Bot.init()
    state.things += bot
    check bot.can_hold
    check not Thing(nil).can_hold

  test "locked things can't, unless you're a god":
    let unit = unit_at(0, 0, 0)
    unit.global_flags += LOCK
    check not unit.can_hold
    state.player.flags += GOD
    check unit.can_hold

  test "nothing can be picked up in Play":
    let unit = unit_at(0, 0, 0)
    state.player.flags += PLAYING
    check not unit.can_hold

  test "picking up a part picks up the whole thing":
    let outer = unit_at(10, 0, 0)
    let inner = Build.init(parent = outer)
    outer.things += inner
    hold(inner)
    check held == outer
    check HELD in outer.global_flags
    check HELD in inner.global_flags

  test "putting it down moves it and lets go":
    let unit = unit_at(0, 0, 0)
    hold(unit)
    let to = Transform.init(origin = vec3(5, 0, 2))
    put_down(to)
    check held.is_nil
    check HELD notin unit.global_flags
    check unit.transform == to
    check unit.placed.before == Transform.init(origin = vec3(0, 0, 0))
    check unit.placed.after == to

  test "putting it back leaves it where it was":
    let unit = unit_at(1, 2, 3)
    hold(unit)
    put_back()
    check held.is_nil
    check HELD notin unit.global_flags
    check unit.transform.origin == vec3(1, 2, 3)

  test "the move tool shows where it goes only while holding something":
    let unit = unit_at(0, 0, 0)
    state.push_flag BLOCK_TARGET_VISIBLE
    check BLOCK_TARGET_VISIBLE notin state.local_flags
    hold(unit)
    check BLOCK_TARGET_VISIBLE in state.local_flags
    put_back()
    check BLOCK_TARGET_VISIBLE notin state.local_flags

suite "Lifting":
  let
    start = Transform.init(origin = vec3(0, 0, -5))
    grab = vec3(0, 1, -5)
    eye = vec3(0, 1, 0)

  test "aiming level keeps it where it is":
    check lifted(start, grab, eye, vec3(0, 0, -1)).get.origin == vec3(0, 0, -5)

  test "aiming higher raises it by whole blocks":
    # 5 away, looking up 2.4 in 5: crosses 2.4 above the grab, so up 2
    let look = vec3(0, 2.4, -5).normalized
    check lifted(start, grab, eye, look).get.origin == vec3(0, 2, -5)

  test "aiming lower lowers it":
    let look = vec3(0, -3.1, -5).normalized
    check lifted(start, grab, eye, look).get.origin == vec3(0, -3, -5)

  test "only its height changes":
    let look = vec3(3, 2, -5).normalized
    let to = lifted(start, grab, eye, look).get
    check to.origin.x == 0
    check to.origin.z == -5

  test "straight up or away from it does nothing":
    check lifted(start, grab, eye, UP).is_none
    check lifted(start, grab, eye, vec3(0, 0, 1)).is_none
