## Properties and queries that every thing has, like `position`, `speed`,
## `color` and `scale`. These commands cross over into the Enu engine
## itself.

import types, vm_bridge_utils

# NOTE: overridden by ScriptController. Only for tests.
var current_active_thing: Thing
proc register_active_impl(self: Thing) =
  current_active_thing = self

proc active_thing_impl(): Thing =
  current_active_thing

proc register_active*(self: Thing) =
  register_active_impl(self)

proc active_thing*(): Thing =
  active_thing_impl()

proc sees_impl*(self: Thing, target: Thing, less_than = 100.0): bool =
  discard

bridged_to_host:
  proc now_seconds*(): float
    ## Seconds since Enu started. `now()` is usually nicer.

  proc write_stack_trace*()
  proc id*(self: Thing): string
    ## The thing's name, like "bot_1729". Every thing has a different one.

  proc position*(self: Thing): Vector3
    ## Where the thing is. Assign to it to teleport:
    ## `position = player.position` (zap!).

  proc local_position*(self: Thing): Vector3
    ## Where the thing is compared to its parent, instead of the world.

  proc start_position*(self: Thing): Vector3
    ## Where the thing starts when the level loads. Assigning moves the
    ## start point, and that sticks around after a reload.

  proc speed*(self: Thing): float
    ## How fast the thing moves or builds. `1` is normal, bigger is
    ## faster, and `ASAP` (`0`) means "all at once" for building. Builds
    ## default to `auto`, which starts slow and speeds up before finishing
    ## ASAP.

  proc `speed=`*(self: Thing, speed: float)
  proc scale*(self: Thing): float
    ## How big the thing is. `1` is normal size, `2` is double, `0.5` is
    ## half. Careful going tiny, it's easy to lose things.

  proc `scale=`*(self: Thing, scale: float)
  proc glow*(self: Thing): float
    ## How much the thing glows. `0` is no glow; crank it up to make
    ## something impossible to miss.

  proc `glow=`*(self: Thing, energy: float)
  proc global*(self: Thing): bool
    ## Whether the thing lives in world space (`true`) or moves around
    ## with its parent (`false`).

  proc `global=`*(self: Thing, global: bool)
  proc rotation*(self: Thing): float
    ## Which way the thing is facing, in degrees. Assign to spin it
    ## around: `rotation = 180` does an about-face.

  proc `rotation=`*(self: Thing, degrees: float)
  proc hit*(self: Thing, node: Thing): bool
  proc `velocity=`*(self: Thing, velocity: Vector3)
  proc velocity*(self: Thing): Vector3
    ## How fast (and which way) the thing is moving right now.

  proc color*(self: Thing): Color
    ## The thing's color. For a Build this is the drawing color, blocks
    ## you draw after changing it use the new color.

  proc `color=`*(self: Thing, color: Color)
  proc show*(self: Thing): bool
    ## Whether the thing is visible. `show = false` makes it vanish.
    ## It's still there. It's just being sneaky.

  proc `show=`*(self: Thing, value: bool)
  proc frame_created*(self: Thing): int
    ## The frame number when the thing was created.

  proc lock*(self: Thing): bool
    ## Locked things can't be edited in the world with the mouse. Good
    ## for finished builds you don't want to nudge by accident.

  proc `lock=`*(self: Thing, value: bool)
  proc reset*(self: Thing, clear = false)
    ## Send the thing back to its start position, rotation and scale.
    ## With `clear = true`, a Build also forgets its drawn blocks.

  proc adopt*(self: Thing, thing: Thing)
    ## Make another thing this thing's child, so it moves when this one
    ## moves.

  proc release*(self: Thing)
    ## Let a child thing go free. The opposite of `adopt`.

  proc press_action*(name: string)
    ## Pretend a button was pressed, like "jump". `release_action`
    ## lets it go. Yes, this means you can prank the player.

  proc release_action*(name: string)
  proc load_level*(level: string, world = "")
    ## Switch to a different level.

  proc reset_level*()
    ## Restart the current level from scratch.

  proc level_name*(): string
    ## The name of the current level.

  proc world_name*(): string
    ## The name of the current world.

  proc current_colliders*(self: Thing, name: string): seq[Thing]
  proc all_builds*(): seq[Build]
    ## Every build in the world. `Build.all` is the fancier way.

  proc all_bots*(): seq[Bot]
    ## Every bot in the world. `Bot.all` is the fancier way.

  proc all_signs*(): seq[Sign]
    ## Every sign in the world.

  proc all_players*(): seq[Player]
    ## Everyone playing right now.

  proc all_things*(): seq[Thing]
    ## Every thing in the world: builds, bots, signs and players.

  proc find_voxel_overlaps*(limit: int = 50): string
  proc things_in_box*(
    x1: float, y1: float, z1: float, x2: float, y2: float, z2: float
  ): seq[Thing]
    ## Every thing inside the box between two corners.

  proc floor_at*(x: float, z: float): int
    ## The height of the ground at a spot, the y of the highest solid
    ## block, plus 1.

  proc clear_box*(
    x1: float, y1: float, z1: float, x2: float, y2: float, z2: float
  ): bool
    ## Erase every block inside the box between two corners.

  proc bounds*(self: Thing): WorldBox
    ## The invisible box around the thing and everything it's made of.

  proc overlaps*(a: Thing, b: Thing): bool
    ## `true` if two things' boxes overlap.

  proc things_overlapping*(box: WorldBox): seq[Thing]
    ## Every thing whose box overlaps this one.

  proc box_is_free*(box: WorldBox): bool
    ## `true` if nothing is in the box, handy for checking a spot
    ## before building there.

  proc bounds_at*(
    self: Build, position: Vector3, rotation: float = 0.0, scale: float = 0.0
  ): WorldBox
    ## The box this build *would* take up at a different position,
    ## rotation or scale. Check before you leap.

  proc added_things*(): seq[Thing]
  proc register_template_node*(self: Thing, name: string)

  # TODO: These should be in base_bridge_private, but are currently needed outside of base_api.
  proc echo_console*(msg: string)
  proc exit*(exit_code = 0, msg = "")
  proc new_instance*(src, dest: Thing)
  proc exec_instance*(self: Thing)
  proc capture_start_transform*(self: Thing)
  proc wake*(self: Thing)
  proc create_new*(self: Thing)
  proc frame_count*(): int
  proc report_test_results*(passed: int, failed: int, total: int)
    ## Report one script's test tally to the host. The host sums these
    ## across every script for the run's exit code and final summary.
