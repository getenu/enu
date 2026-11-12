import unittest2
import core
import models/[states, colors, players]

suite "Per-player state":
  var me, other: Player

  setup:
    state = GameState.init
    me = Player.init(id = "player-me")
    other = Player.init(id = "player-other")
    state.player = me
    state.watch_player

  test "players don't share a toolbar or modes":
    other.tool_colors[0] = ACTION_COLORS[RED]
    other.tools -= PLACE_BOT
    other.flags += GOD
    check me.tool_colors[0] == ACTION_COLORS[BLUE]
    check PLACE_BOT in me.tools
    check GOD notin me.flags

  test "playing and flying exclude each other":
    me.flags += FLYING
    me.flags += PLAYING
    check me.flags.value == {PLAYING}
    me.flags += FLYING
    check me.flags.value == {FLYING}

  test "grounding a flying player":
    me.flags += FLYING
    me.set_flag FLY_DISABLED, true
    check me.flags.value == {FLY_DISABLED}
    me.flags += FLYING
    check me.flags.value == {FLY_DISABLED}

  test "a level without tools":
    me.reset_toolbar(show_tools = false)
    check me.tools.value == {}
    me.tool_colors[1] = ACTION_COLORS[BLACK]
    me.reset_toolbar(show_tools = true)
    check me.tools.value == {CODE_MODE .. PLACE_BOT}
    check me.tool_colors.value == DEFAULT_TOOL_COLORS

  test "this instance's player drives its UI flags":
    state.push_flag MOUSE_CAPTURED
    state.replace_flag BLOCK_TARGET_VISIBLE
    me.flags += PLAYING
    check BLOCK_TARGET_VISIBLE notin state.local_flags
    check RETICLE_VISIBLE in state.local_flags
    me.coding = Thing()
    check EDITOR_VISIBLE notin state.local_flags
    me.flags -= PLAYING
    me.coding = Thing()
    check EDITOR_VISIBLE in state.local_flags

  test "another player's modes leave this instance's UI alone":
    state.push_flag MOUSE_CAPTURED
    state.replace_flag BLOCK_TARGET_VISIBLE
    other.flags += PLAYING
    other.coding = Thing()
    check BLOCK_TARGET_VISIBLE in state.local_flags
    check EDITOR_VISIBLE notin state.local_flags
