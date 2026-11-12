import unittest2
import core
import models/[states, colors, players]

suite "Tool availability":
  var player: Player

  setup:
    state = GameState.init
    player = Player.init(id = "player-me")
    state.player = player

  test "defaults to all real tools, blue active":
    check player.tool == BLUE_BLOCK
    for tool in CODE_MODE .. PLACE_BOT:
      check tool in player.tools
    check NONE notin player.tools
    check DISABLED notin player.tools

  test "removing the active tool drops to NONE":
    player.tools -= BLUE_BLOCK
    check player.tool == NONE

  test "removing a non-active tool leaves the active tool alone":
    player.tools -= RED_BLOCK
    check player.tool == BLUE_BLOCK

  test "selecting an unavailable tool is a no-op":
    player.tools -= RED_BLOCK
    player.select_tool RED_BLOCK
    check player.tool == BLUE_BLOCK

  test "selecting an available tool works":
    player.select_tool GREEN_BLOCK
    check player.tool == GREEN_BLOCK

  test "removing every tool stays NONE with no auto-recovery":
    player.tools.clear()
    check player.tool == NONE
    # a tool coming back does not auto-select it
    player.tools += BLUE_BLOCK
    check player.tool == NONE
    # the player is unstuck only by an explicit selection
    player.select_tool BLUE_BLOCK
    check player.tool == BLUE_BLOCK

  test "cycling skips unavailable tools and NONE/DISABLED":
    player.tools -= RED_BLOCK
    player.tools -= GREEN_BLOCK
    player.tool = BLUE_BLOCK # red/green gone, next available is black
    # removing the actives above could have dropped us to NONE; reset explicitly
    state.update_action_index(1)
    check player.tool == BLACK_BLOCK

  test "cycling is a no-op when no tools are available":
    player.tools.clear()
    check player.tool == NONE
    state.update_action_index(1)
    check player.tool == NONE

  test "NONE hides the block target and keeps the reticle, like play mode":
    player.tool = NONE
    state.push_flag MOUSE_CAPTURED
    state.push_flag BLOCK_TARGET_VISIBLE
    check BLOCK_TARGET_VISIBLE notin state.local_flags
    check RETICLE_VISIBLE in state.local_flags

suite "Tool colors":
  var player: Player

  setup:
    state = GameState.init
    player = Player.init(id = "player-me")
    state.player = player

  test "the block tools start with the named colors":
    player.tool = BLUE_BLOCK
    check player.selected_color == ACTION_COLORS[BLUE]
    player.tool = BROWN_BLOCK
    check player.selected_color == ACTION_COLORS[BROWN]

  test "a block tool places its own color":
    let orange = col"ff8800"
    player.tool_colors[1] = orange
    player.tool = RED_BLOCK
    check player.selected_color == orange
    player.tool = BLUE_BLOCK
    check player.selected_color == ACTION_COLORS[BLUE]
