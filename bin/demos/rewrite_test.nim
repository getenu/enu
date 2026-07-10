import std/times except seconds
import client
import core, models/[builds, units, colors, voxels]

Enu.client.connect
discard Enu.client.tick_until(3.seconds, Enu.client.connected)
discard Enu.client.tick_until(10.seconds, "root_units" in Enu.client.ctx)

let build = Build.init(30.0, 0.0, 30.0, save = false)
Enu.things.add build
discard Enu.client.tick_until(2.seconds, false)

build.buffer:
  for x in 0 ..< 12:
    for y in 0 ..< 12:
      for z in 0 ..< 12:
        build.draw(
          vec3(x.float, y.float, z.float), (TRANSIENT, ACTION_COLORS[RED])
        )
discard Enu.client.tick_until(3.seconds, false)

build.voxels.clear()
build.buffer:
  for x in 0 ..< 3:
    for y in 0 ..< 3:
      for z in 0 ..< 3:
        build.draw(
          vec3(x.float, y.float, z.float), (TRANSIENT, ACTION_COLORS[BLUE])
        )
discard Enu.client.tick_until(3.seconds, false)
echo "REWRITTEN - only a small blue cube should remain"
Enu.client.every(1.second):
  discard
