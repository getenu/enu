import std/[os, math]
import client
import core, models/[bots, builds, units, colors]

Enu.client.connect
discard Enu.client.tick_until(3.seconds, Enu.client.connected)

let build = Build.init(-20, 0, 20)
build.voxels.immediate = true
Enu.units.add build
Enu.client.tick

let palette = [col"fc0e0b", col"14f707", col"0067ff", col"d9eed8"]
echo "drawing large mathy sine surface (40x40)..."
for x in 0 ..< 40:
  for z in 0 ..< 40:
    let h = (sin(x.float / 5.0) + cos(z.float / 5.0)) * 4.0
    let y = int(round(h)) + 8
    build.draw(vec3(x.float, y.float, z.float), (MANUAL, palette[(x + z) mod 4]))
  Enu.client.tick
echo "BUILD=" & build.id
Enu.client.every(1.second):
  discard
