import unittest2
import core
import models

# Which of the world and the panels has the keyboard, and where the pointer is.

proc focus(): set[LocalStateFlags] =
  state.local_flags.value * FOCUS_FLAGS

suite "Focus flags":
  setup:
    state = GameState.init
    state.player = Player.init(id = "player-me")
    state.resolve_flags

  test "the world has the keyboard when nothing else is open":
    check focus() == {VIEWPORT_FOCUSED}
    state.push_flag MOUSE_CAPTURED
    check focus() == {VIEWPORT_FOCUSED}
    check POINTER_IN_VIEWPORT in state.local_flags

  test "opening the editor focuses it and frees the mouse":
    state.push_flag MOUSE_CAPTURED
    state.push_flag EDITOR_VISIBLE
    check focus() == {EDITOR_FOCUSED}
    check MOUSE_CAPTURED notin state.local_flags

  test "hovering the world doesn't take the keyboard":
    state.push_flag EDITOR_VISIBLE
    state.push_flag POINTER_IN_VIEWPORT
    check focus() == {EDITOR_FOCUSED}
    check POINTER_IN_VIEWPORT in state.local_flags

  test "clicking the world takes it; Esc gives it back to the editor":
    state.push_flag EDITOR_VISIBLE
    state.push_flag VIEWPORT_FOCUSED
    check focus() == {VIEWPORT_FOCUSED}
    check EDITOR_VISIBLE in state.local_flags
    check state.try_pop(VIEWPORT_FOCUSED) * FOCUS_FLAGS == {EDITOR_FOCUSED}
    state.pop_flag VIEWPORT_FOCUSED
    check focus() == {EDITOR_FOCUSED}

  test "leaving command mode goes back to the editor, even after a click":
    state.push_flag MOUSE_CAPTURED
    state.push_flag EDITOR_VISIBLE
    state.push_flag VIEWPORT_FOCUSED
    state.push_flag COMMAND_MODE
    check focus() == {VIEWPORT_FOCUSED}
    check MOUSE_CAPTURED in state.local_flags
    state.pop_flag COMMAND_MODE
    check focus() == {EDITOR_FOCUSED}
    check MOUSE_CAPTURED notin state.local_flags

  test "the last panel clicked has the keyboard":
    state.push_flag EDITOR_VISIBLE
    state.push_flag DOCS_VISIBLE
    state.push_flag SETTINGS_VISIBLE
    check focus() == {SETTINGS_FOCUSED}
    state.push_flag EDITOR_FOCUSED
    check focus() == {EDITOR_FOCUSED}
    state.push_flag DOCS_FOCUSED
    check focus() == {DOCS_FOCUSED}
    state.push_flag EDITOR_FOCUSED
    check focus() == {EDITOR_FOCUSED}

  test "closing the focused panel hands the keyboard to the one before":
    state.push_flag EDITOR_VISIBLE
    state.push_flag DOCS_VISIBLE
    check focus() == {DOCS_FOCUSED}
    state.pop_flag DOCS_VISIBLE
    check focus() == {EDITOR_FOCUSED}
    state.pop_flag EDITOR_VISIBLE
    check focus() == {VIEWPORT_FOCUSED}

  test "a hidden panel can't keep the keyboard":
    state.push_flag EDITOR_VISIBLE
    state.push_flag EDITOR_FOCUSED
    state.player.flags += PLAYING
    state.resolve_flags
    check EDITOR_VISIBLE notin state.local_flags
    check focus() == {VIEWPORT_FOCUSED}

  test "a captured mouse aims at the world with the console open":
    state.push_flag MOUSE_CAPTURED
    state.push_flags CONSOLE_VISIBLE, CONSOLE_FOCUSED
    check focus() == {VIEWPORT_FOCUSED}
    check POINTER_IN_VIEWPORT in state.local_flags
    state.pop_flag MOUSE_CAPTURED
    check focus() == {CONSOLE_FOCUSED}

  test "the reticle shows only with a captured mouse":
    state.push_flag RETICLE_VISIBLE
    check RETICLE_VISIBLE notin state.local_flags
    state.push_flag MOUSE_CAPTURED
    check RETICLE_VISIBLE in state.local_flags
    state.replace_flag BLOCK_TARGET_VISIBLE
    check BLOCK_TARGET_VISIBLE in state.local_flags
    check RETICLE_VISIBLE notin state.local_flags

  test "hovering back in while captured still counts once the mouse is freed":
    # The hidden cursor drifts over the toolbar and back while captured; the
    # pointer flag is forced on then, so its re-push must still be recorded.
    state.push_flag POINTER_IN_VIEWPORT
    state.push_flag MOUSE_CAPTURED
    state.pop_flag POINTER_IN_VIEWPORT
    state.push_flag POINTER_IN_VIEWPORT
    state.pop_flag MOUSE_CAPTURED
    check POINTER_IN_VIEWPORT in state.local_flags
