import math
# SpiralTree prototype: a parameterised tree with internal randomness —
# two instances with identical params still differ. Helical trunk of
# cylinder slices, radial branch rings, off-centre crown.
# Capture proto params into locals before drawing: passing a param
# straight into a drawing call resolves to its accessor, not its value.
# Instantiate from a DIFFERENT script (see tree_showcase.nim) — never
# call SpiralTree.new in this file.
name SpiralTree(trunk_height = 26, trunk_color = brown, leaf_color = green, twist = 0.22)

let th = trunk_height
let tw = twist
let tcol = trunk_color
let lcol = leaf_color

# helical trunk with a small random radius wobble per slice
th.times(i):
  let r = 1.2 + (0.0 .. 0.7)
  cylinder(
    size = 2, height = 1,
    at = vec3(sin(i.float * tw) * r, i.float, -(cos(i.float * tw) * r)),
    color = tcol,
  )

# radial branch rings — random count of rings, branches, and lengths
let rings = 3 + (1 .. 2)
rings.times(ring):
  let ry = (5 + ring * (th div (rings + 1))).float
  let cx = sin(ry * tw) * 1.2
  let cz = -(cos(ry * tw) * 1.2)
  let branches = 5 + (0 .. 3)
  branches.times(b):
    let ang = b.float * (2.0 * PI / branches.float) + (0.0 .. 0.5)
    let blen = 3 + (1 .. 3)
    blen.times(s):
      let t = (s + 1).float / blen.float
      place(
        (cx + cos(ang) * blen.float * t).int,
        (ry + t * 2.0).int,
        (cz + sin(ang) * blen.float * t).int,
        lcol,
      )

# crown canopy — random size, slightly off-centre
let crown = 6 + (0 .. 4)
sphere(
  size = crown,
  at = vec3(
    sin(th.float * tw) * 1.2 + (-1.0 .. 1.0),
    th.float - 1.0,
    -(cos(th.float * tw) * 1.2) + (-1.0 .. 1.0),
  ),
  color = lcol,
)
