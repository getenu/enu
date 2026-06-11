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
  proc write_stack_trace*()
  proc id*(self: Unit): string
  proc position*(self: Unit): Vector3
  proc local_position*(self: Unit): Vector3
  proc start_position*(self: Unit): Vector3
  proc speed*(self: Unit): float
  proc `speed=`*(self: Unit, speed: float)
  proc scale*(self: Unit): float
  proc `scale=`*(self: Unit, scale: float)
  proc glow*(self: Unit): float
  proc `glow=`*(self: Unit, energy: float)
  proc global*(self: Unit): bool
  proc `global=`*(self: Unit, global: bool)
  proc rotation*(self: Unit): float
  proc `rotation=`*(self: Unit, degrees: float)
  proc hit*(self: Unit, node: Unit): bool
  proc `velocity=`*(self: Unit, velocity: Vector3)
  proc velocity*(self: Unit): Vector3
  proc color*(self: Unit): Colors
  proc `color=`*(self: Unit, color: Colors)
  proc show*(self: Unit): bool
  proc `show=`*(self: Unit, value: bool)
  proc frame_created*(self: Unit): int
  proc lock*(self: Unit): bool
  proc `lock=`*(self: Unit, value: bool)
  proc reset*(self: Unit, clear = false)
  proc press_action*(name: string)
  proc release_action*(name: string)
  proc load_level*(level: string, world = "")
  proc reset_level*()
  proc level_name*(): string
  proc world_name*(): string
  proc current_colliders*(self: Unit, name: string): seq[Unit]
  proc all_builds*(): seq[Build]
  proc all_bots*(): seq[Bot]
  proc all_signs*(): seq[Sign]
  proc all_players*(): seq[Player]
  proc all_units*(): seq[Unit]
  proc find_voxel_overlaps*(limit: int = 50): string
  proc units_in_box*(
    x1: float, y1: float, z1: float, x2: float, y2: float, z2: float
  ): seq[Unit]

  proc floor_at*(x: float, z: float): int

  proc clear_box*(
    x1: float, y1: float, z1: float, x2: float, y2: float, z2: float
  ): bool

  proc bounds*(self: Unit): WorldBox
  proc overlaps*(a: Unit, b: Unit): bool
  proc units_overlapping*(box: WorldBox): seq[Unit]
  proc box_is_free*(box: WorldBox): bool
  proc bounds_at*(
    self: Build, position: Vector3, rotation: float = 0.0, scale: float = 0.0
  ): WorldBox

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
