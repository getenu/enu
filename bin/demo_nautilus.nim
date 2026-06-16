import std/math
import client
import core, models/[builds, units, colors]

Enu.client.connect

const
  turns = 7.0
  a = 1.4
  b = 0.10
  tube_ratio = 0.22
  line_density = 0
  block_kind = MANUAL
let
  body_color = col"000000"
  line_colors = [col"fc0e0b", col"0067ff", col"14f707", col"d9eed8"]

let build = Build.init(0, 0, -150, save = true)
Enu.units.add build

var theta = 0.0
build.buffer:
  while theta < turns * 2 * PI:
    let r = a * exp(b * theta)
    let tube = r * tube_ratio
    let cx = r * cos(theta)
    let cz = r * sin(theta)
    let rim = max(10, int(tube * 7))
    for i in 0 ..< rim:
      let phi = i.float / rim.float * 2 * PI
      let px = cx + tube * cos(phi) * cos(theta)
      let py = tube * (1.0 + sin(phi))
      let pz = cz + tube * cos(phi) * sin(theta)
      let num_lines = 1 shl clamp(line_density + int(log2(max(1.0, tube))), 0, 6)
      let slot = (i * num_lines) div rim
      let is_line = i == 0 or slot != ((i - 1) * num_lines) div rim
      let color =
        if is_line:
          line_colors[
            int(slot.float / num_lines.float * 16.0) mod line_colors.len
          ]
        else:
          body_color
      build.draw(vec3(px.round, py.round, pz.round), (block_kind, color))
    theta += 0.7 / r
