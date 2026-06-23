import client, models/[builds, colors]

Enu.client.connect
let build = Build.init(0, 0, -150)
Enu.units.add build
for i in 0 .. 10:
  build.draw vec3(0, i, 0), (COMPUTED, col"000000")