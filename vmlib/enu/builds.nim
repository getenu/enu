import std/[strutils]
import types, base_api, vm_bridge_utils

bridged_to_host:
  proc drawing*(self: Build): bool
  proc `drawing=`*(self: Build, drawing: bool)
  proc initial_position(self: Build): Vector3
  proc all_builds(): seq[Build]
  proc save*(self: Build, name = "default")
  proc restore*(self: Build, name = "default")
  proc draw_position*(self: Build): Vector3
  proc `draw_position=`*(self: Build, value: Vector3)

proc `draw_position=`*(self: Build, unit: Unit) =
  self.draw_position = unit.position

proc all*(_: type Build): seq[Build] =
  all_builds()

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
