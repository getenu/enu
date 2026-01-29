import std/[strutils]
import types, base_api, vm_bridge_utils

bridged_to_host:
  proc drawing*(self: Build): bool
  proc `drawing=`*(self: Build, drawing: bool)
  proc initial_position(self: Build): Vector3
  proc save*(self: Build, name = "default")
  proc restore*(self: Build, name = "default")
  proc draw_position*(self: Build): Vector3
  proc `draw_position=`*(self: Build, value: Vector3)
  proc has_block_at*(position: Vector3): bool
  proc block_color_at*(position: Vector3): Colors
  proc begin_asap*(self: Build)
  proc end_asap*(self: Build)
  proc place_block*(self: Build, position: Vector3, color: Colors)
    ## Places a MANUAL block at the given position. Used for testing persistence.

  proc save_level_now*()
    ## Triggers an immediate level save. Used for testing persistence.

  proc reload_unit*(self: Build)
    ## Reloads the Build's voxel data from disk without stopping the script.

template asap*(body: untyped) =
  ## Execute build commands instantly without incremental updates.
  let self = Build(active_unit())
  let prev_speed = self.speed
  self.speed = ASAP
  try:
    body
  finally:
    self.speed = prev_speed

proc `draw_position=`*(self: Build, unit: Unit) =
  self.draw_position = unit.position

proc go_home*(self: Build) =
  self.rotation = 0
  self.scale = 1
  self.glow = 0
  self.forward self.position.z - self.start_position.z, 2
  self.left self.position.x - self.start_position.x, 2
  self.down self.position.y - self.start_position.y, 2

proc fill_square*(self: Build, length = 1) =
  for l in 0 .. length:
    for i in 0 .. 3:
      self.forward(length - l, 2)
      self.right(1, 2)
