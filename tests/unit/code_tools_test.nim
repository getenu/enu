import unittest2
import core
import models
import models/states {.all.}

# The code tool's toolbar button holds a stack of tools: the one in the
# toolbar, then the rest above it, bottom to top.

suite "Code tool stack":
  setup:
    state = GameState.init
    state.player = Player.init(id = "player-me")
    code_stack = @[]
    state.player.tool = CODE_MODE

  test "it starts with the code tool in the toolbar":
    check code_tools() == @[CODE_MODE, MOVE_TOOL, LIFT_TOOL, TURN_TOOL]

  test "up brings the next tool down and sends the old one to the top":
    state.stack_up
    check state.player.tool == MOVE_TOOL
    check code_tools() == @[MOVE_TOOL, LIFT_TOOL, TURN_TOOL, CODE_MODE]

  test "down brings the top tool down and bumps the old one to the bottom":
    state.stack_down
    check state.player.tool == TURN_TOOL
    check code_tools() == @[TURN_TOOL, CODE_MODE, MOVE_TOOL, LIFT_TOOL]
    state.stack_up
    check state.player.tool == CODE_MODE
    check code_tools() == @[CODE_MODE, MOVE_TOOL, LIFT_TOOL, TURN_TOOL]

  test "it goes all the way round":
    for _ in 1 .. 4:
      state.stack_up
    check state.player.tool == CODE_MODE

  test "pressing the code button again is up":
    state.select_or_modify CODE_MODE
    check state.player.tool == MOVE_TOOL

  test "picking a tool in the stack brings it down":
    state.player.select_tool LIFT_TOOL
    check code_tools() == @[LIFT_TOOL, TURN_TOOL, CODE_MODE, MOVE_TOOL]

  test "the code button keeps the tool last in it":
    state.stack_up
    state.player.tool = BLUE_BLOCK
    state.select_or_modify CODE_MODE
    check state.player.tool == MOVE_TOOL

  test "cycling tools stops once on the code button":
    state.stack_up
    state.update_action_index(1)
    check state.player.tool == BLUE_BLOCK
    state.update_action_index(-1)
    check state.player.tool == MOVE_TOOL

  test "the stack goes with the code tool":
    state.player.tools -= CODE_MODE
    state.player.select_tool MOVE_TOOL
    check state.player.tool == NONE
    state.player.tools += CODE_MODE
    state.player.select_tool MOVE_TOOL
    check state.player.tool == MOVE_TOOL
    state.player.tools -= CODE_MODE
    check state.player.tool == NONE

  test "the stack's tools don't place blocks":
    state.stack_up
    check state.player.selected_color == ACTION_COLORS[ERASER]
    check CREATE_MODE notin state.local_flags

  test "the block tools' stack is create mode":
    state.player.tool = BLUE_BLOCK
    state.stack_up
    check state.player.tool == BLUE_BLOCK
    check code_tools()[0] == CODE_MODE
