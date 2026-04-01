import std/[strutils, math]
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

proc place*(self: Build, x, y, z: int, color: Colors) =
  ## Place a single block at local integer coordinates.
  self.place_block((x.float, y.float, z.float), color)

template place*(x, y, z: int, color: Colors) =
  ## Place a single block at local integer coords in a build script.
  Build(active_unit()).place(x, y, z, color)

proc fill_box*(self: Build, x1, y1, z1, x2, y2, z2: int, color: Colors) =
  ## Fill a box region with blocks. Use eraser color to hollow out.
  for y in min(y1, y2) .. max(y1, y2):
    for x in min(x1, x2) .. max(x1, x2):
      for z in min(z1, z2) .. max(z1, z2):
        self.place_block((x.float, y.float, z.float), color)

template fill_box*(x1, y1, z1, x2, y2, z2: int, color: Colors) =
  ## Fill a box region in a build script.
  Build(active_unit()).fill_box(x1, y1, z1, x2, y2, z2, color)

proc fill_sphere*(self: Build, cx, cy, cz: int, radius: float, color: Colors) =
  ## Fill a sphere of blocks centered at (cx, cy, cz).
  let r = radius.ceil.int
  for y in cy - r .. cy + r:
    for x in cx - r .. cx + r:
      for z in cz - r .. cz + r:
        let dx = x - cx
        let dy = y - cy
        let dz = z - cz
        if sqrt((dx*dx + dy*dy + dz*dz).float) <= radius:
          self.place_block((x.float, y.float, z.float), color)

template fill_sphere*(cx, cy, cz: int, radius: float, color: Colors) =
  ## Fill a sphere in a build script.
  Build(active_unit()).fill_sphere(cx, cy, cz, radius, color)

proc fill_cylinder*(self: Build, cx, y1, y2, cz: int, radius: float, color: Colors) =
  ## Fill a vertical cylinder from y1 to y2, centered at (cx, cz).
  let r = radius.ceil.int
  for y in min(y1, y2) .. max(y1, y2):
    for x in cx - r .. cx + r:
      for z in cz - r .. cz + r:
        let dx = x - cx
        let dz = z - cz
        if sqrt((dx*dx + dz*dz).float) <= radius:
          self.place_block((x.float, y.float, z.float), color)

template fill_cylinder*(cx, y1, y2, cz: int, radius: float, color: Colors) =
  ## Fill a vertical cylinder in a build script.
  Build(active_unit()).fill_cylinder(cx, y1, y2, cz, radius, color)
