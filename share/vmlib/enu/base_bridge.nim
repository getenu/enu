## Properties and queries that every unit has, like `position`, `speed`,
## `color` and `scale`. These commands cross over into the Enu engine
## itself.

import types, vm_bridge_utils

# NOTE: overridden by ScriptController. Only for tests.
var current_active_unit: Unit
proc register_active_impl(self: Unit) =
  current_active_unit = self

proc active_unit_impl(): Unit =
  current_active_unit

proc register_active*(self: Unit) =
  register_active_impl(self)

proc active_unit*(): Unit =
  active_unit_impl()

proc sees_impl*(self: Unit, target: Unit, less_than = 100.0): bool =
  discard

bridged_to_host:
  proc now_seconds*(): float
    ## Seconds since Enu started. `now()` is usually nicer.

  proc write_stack_trace*()
  proc id*(self: Unit): string
    ## The unit's name, like "bot_1729". Every unit has a different one.

  proc position*(self: Unit): Vector3
    ## Where the unit is. Assign to it to teleport:
    ## `position = player.position` (zap!).

  proc local_position*(self: Unit): Vector3
    ## Where the unit is compared to its parent, instead of the world.

  proc start_position*(self: Unit): Vector3
    ## Where the unit starts when the level loads. Assigning moves the
    ## start point, and that sticks around after a reload.

  proc speed*(self: Unit): float
    ## How fast the unit moves or builds. `1` is normal, bigger is
    ## faster, and `0` means "all at once" for building.

  proc `speed=`*(self: Unit, speed: float)
  proc scale*(self: Unit): float
    ## How big the unit is. `1` is normal size, `2` is double, `0.5` is
    ## half. Careful going tiny — it's easy to lose things.

  proc `scale=`*(self: Unit, scale: float)
  proc glow*(self: Unit): float
    ## How much the unit glows. `0` is no glow; crank it up to make
    ## something impossible to miss.

  proc `glow=`*(self: Unit, energy: float)
  proc global*(self: Unit): bool
    ## Whether the unit lives in world space (`true`) or moves around
    ## with its parent (`false`).

  proc `global=`*(self: Unit, global: bool)
  proc rotation*(self: Unit): float
    ## Which way the unit is facing, in degrees. Assign to spin it
    ## around: `rotation = 180` does an about-face.

  proc `rotation=`*(self: Unit, degrees: float)
  proc hit*(self: Unit, node: Unit): bool
  proc `velocity=`*(self: Unit, velocity: Vector3)
  proc velocity*(self: Unit): Vector3
    ## How fast (and which way) the unit is moving right now.

  proc color*(self: Unit): Colors
    ## The unit's color. For a Build this is the drawing color — blocks
    ## you draw after changing it use the new color.

  proc `color=`*(self: Unit, color: Colors)
  proc show*(self: Unit): bool
    ## Whether the unit is visible. `show = false` makes it vanish.
    ## It's still there. It's just being sneaky.

  proc `show=`*(self: Unit, value: bool)
  proc frame_created*(self: Unit): int
    ## The frame number when the unit was created.

  proc lock*(self: Unit): bool
    ## Locked units can't be edited in the world with the mouse. Good
    ## for finished builds you don't want to nudge by accident.

  proc `lock=`*(self: Unit, value: bool)
  proc reset*(self: Unit, clear = false)
    ## Send the unit back to its start position, rotation and scale.
    ## With `clear = true`, a Build also forgets its drawn blocks.

  proc adopt*(self: Unit, unit: Unit)
    ## Make another unit this unit's child, so it moves when this one
    ## moves.

  proc release*(self: Unit)
    ## Let a child unit go free. The opposite of `adopt`.

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

  proc current_colliders*(self: Unit, name: string): seq[Unit]
  proc all_builds*(): seq[Build]
    ## Every build in the world. `Build.all` is the fancier way.

  proc all_bots*(): seq[Bot]
    ## Every bot in the world. `Bot.all` is the fancier way.

  proc all_signs*(): seq[Sign]
    ## Every sign in the world.

  proc all_players*(): seq[Player]
    ## Everyone playing right now.

  proc all_units*(): seq[Unit]
    ## Every unit in the world — builds, bots, signs and players.

  proc find_voxel_overlaps*(limit: int = 50): string
  proc units_in_box*(
    x1: float, y1: float, z1: float, x2: float, y2: float, z2: float
  ): seq[Unit]
    ## Every unit inside the box between two corners.

  proc floor_at*(x: float, z: float): int
    ## The height of the ground at a spot — the y of the highest solid
    ## block, plus 1.

  proc clear_box*(
    x1: float, y1: float, z1: float, x2: float, y2: float, z2: float
  ): bool
    ## Erase every block inside the box between two corners.

  proc bounds*(self: Unit): WorldBox
    ## The invisible box around the unit and everything it's made of.

  proc overlaps*(a: Unit, b: Unit): bool
    ## `true` if two units' boxes overlap.

  proc units_overlapping*(box: WorldBox): seq[Unit]
    ## Every unit whose box overlaps this one.

  proc box_is_free*(box: WorldBox): bool
    ## `true` if nothing is in the box — handy for checking a spot
    ## before building there.

  proc bounds_at*(
    self: Build, position: Vector3, rotation: float = 0.0, scale: float = 0.0
  ): WorldBox
    ## The box this build *would* take up at a different position,
    ## rotation or scale. Check before you leap.

  proc added_units*(): seq[Unit]
  proc register_template_node*(self: Unit, name: string)

  # TODO: These should be in base_bridge_private, but are currently needed outside of base_api.
  proc echo_console*(msg: string)
  proc exit*(exit_code = 0, msg = "")
  proc new_instance*(src, dest: Unit)
  proc exec_instance*(self: Unit)
  proc capture_start_transform*(self: Unit)
  proc wake*(self: Unit)
  proc create_new*(self: Unit)
  proc frame_count*(): int
  proc signal_test_complete*(exit_code: int)
