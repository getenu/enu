import unittest2
import core
import models/[states, colors, builds, bots, players]

# The {.ed.} field pragmas in types.nim set each field's Ed flags, ids and
# defaults through the constructors. A field that silently fell back to the
# defaults would still compile and mostly work, so check what was created.

const synced = {SYNC_LOCAL, SYNC_REMOTE}

suite "Ed fields are created as declared":
  setup:
    state = GameState.init

  test "things":
    let build = Build.init(id = "ed_flags_build")
    check build.global_flags.flags == synced
    check build.local_flags.flags == {SYNC_LOCAL}
    check build.things.flags == synced + {OWNS_MEMBERS}
    check build.collisions.flags == {SYNC_LOCAL}
    check build.eval_value.flags == {SYNC_LOCAL}
    check build.draw_transform_value.flags == {}
    check build.scale == 1.0
    check build.sealed_frames
    check build.frames_loop

    let bot = Bot.init(id = "ed_flags_bot")
    check bot.local_flags.flags == {SYNC_LOCAL}
    check bot.transform_value.flags == synced

  test "the player rejects stale body writes":
    let player = Player.init(id = "ed_flags_player")
    check player.transform_value.flags == synced + {REJECT_STALE}
    check player.velocity_value.flags == synced + {REJECT_STALE}
    check player.block_log_entries.flags == {SYNC_LOCAL}

  test "game state":
    check state.things.id == "root_things"
    check state.things.flags == synced + {OWNS_MEMBERS}
    check state.config_value.id == "config"
    check state.config_value.flags == {SYNC_LOCAL}
    check state.level_name_value.id == "level_name"
    check state.level_name_value.flags == synced
    check state.global_flags.id == "state_global_flags"
    check state.local_flags.flags == {SYNC_LOCAL}
    check state.test_exit_code == -1
    check state.gravity == -80.0
    check state.show_tools
