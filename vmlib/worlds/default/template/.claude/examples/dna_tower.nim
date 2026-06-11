import math
# DNA tower (~240 m): twin ribbons spiralling around an open axis, tied
# by rungs every 12 levels. Math-driven placement (cos/sin into box/place)
# — the opposite of turtle drawing, and the way to build structure around
# empty space. 2x2 ribbon cross-sections so they read at a distance.
let h = 240
let r = 8.0
for y in 0 .. h:
  let a = y.float * 0.1
  let x1 = cos(a) * r
  let z1 = sin(a) * r
  let x2 = cos(a + PI) * r
  let z2 = sin(a + PI) * r
  box(vec3(x1.int, y, z1.int), vec3(x1.int + 1, y, z1.int + 1), white)
  box(vec3(x2.int, y, z2.int), vec3(x2.int + 1, y, z2.int + 1), white)
  if y mod 12 == 0:
    10.times(t):
      let f = t.float / 9.0
      place((x1 + (x2 - x1) * f).int, y, (z1 + (z2 - z1) * f).int, black)
