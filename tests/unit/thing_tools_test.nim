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
