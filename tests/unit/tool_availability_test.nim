import unittest2
import core
import models/states

suite "Tool availability":
  setup:
    state = GameState.init

  test "defaults to all real tools, blue active":
    check state.tool == BLUE_BLOCK
    for tool in CODE_MODE .. PLACE_BOT:
      check tool in state.tools
    check NONE notin state.tools
    check DISABLED notin state.tools

  test "removing the active tool drops to NONE":
    state.tools -= BLUE_BLOCK
    check state.tool == NONE

  test "removing a non-active tool leaves the active tool alone":
    state.tools -= RED_BLOCK
    check state.tool == BLUE_BLOCK

  test "selecting an unavailable tool is a no-op":
    state.tools -= RED_BLOCK
    state.select_tool RED_BLOCK
    check state.tool == BLUE_BLOCK

  test "selecting an available tool works":
    state.select_tool GREEN_BLOCK
    check state.tool == GREEN_BLOCK

  test "removing every tool stays NONE with no auto-recovery":
    state.tools.clear()
    check state.tool == NONE
    # a tool coming back does not auto-select it
    state.tools += BLUE_BLOCK
    check state.tool == NONE
    # the player is unstuck only by an explicit selection
    state.select_tool BLUE_BLOCK
    check state.tool == BLUE_BLOCK

  test "cycling skips unavailable tools and NONE/DISABLED":
    state.tools -= RED_BLOCK
    state.tools -= GREEN_BLOCK
    state.tool = BLUE_BLOCK # red/green gone, next available is black
    # removing the actives above could have dropped us to NONE; reset explicitly
    state.update_action_index(1)
    check state.tool == BLACK_BLOCK

  test "cycling is a no-op when no tools are available":
    state.tools.clear()
    check state.tool == NONE
    state.update_action_index(1)
    check state.tool == NONE
