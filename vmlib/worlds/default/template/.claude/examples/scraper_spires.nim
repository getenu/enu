# Crystal-shard spires (210 m): a fused cluster of tapering cylinders.
# Fractional `size` values give smooth tapers — a cone is just stacked
# 1-high disks of shrinking diameter. The main shard gets a hollow bore,
# round porthole windows spiralling up its faces, and a doorway; the
# same spire() proc makes castle cone-roofs at smaller sizes.
proc spire(cx, cz, h: int, base: float, col: Colors) =
  h.times(i):
    let d = base * (1.0 - i.float / h.float) + 2.0
    cylinder(size = d, height = 1, at = vec3(cx, i.float, cz), color = col)

spire(0, 0, 210, 20.0, white)
spire(14, -9, 140, 15.0, blue)
spire(-12, -6, 110, 14.0, white)
spire(3, -18, 90, 12.0, blue)
spire(-8, 9, 70, 11.0, white)

cylinder(size = 12, height = 110, at = vec3(0, 1, 0), color = eraser) # bore

var wy = 8
var face = 0
while wy < 100: # round windows spiralling up, alternating faces
  let d = 20.0 * (1.0 - wy.float / 210.0) + 2.0
  let r = d / 2.0
  case face mod 4
  of 0: sphere(size = 4, at = vec3(r, wy.float, 0), color = eraser)
  of 1: sphere(size = 4, at = vec3(0, wy.float, r), color = eraser)
  of 2: sphere(size = 4, at = vec3(-r, wy.float, 0), color = eraser)
  else: sphere(size = 4, at = vec3(0, wy.float, -r), color = eraser)
  wy += 9
  face += 1

cylinder(size = 8, height = 70, at = vec3(14, 1, -9), color = eraser)
box(vec3(13, 1, -4), vec3(15, 4, -1), eraser)
box(vec3(-2, 1, 8), vec3(2, 5, 11), eraser) # main doorway
