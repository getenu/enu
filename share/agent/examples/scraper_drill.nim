# Drilled column (130 m): one smooth cylinder, completely flat outside.
# The interior is carved floor-by-floor with eraser disks (every 5th
# level stays solid as a slab), windows are punched through each face,
# and every 6th floor opens a whole half-face as a balcony. Solid-then-
# carve is often easier than building hollow.
cylinder(size = 19, height = 130, at = vec3(0, 0, 0), color = white)

var y = 1
var level = 0
while y < 126:
  cylinder(size = 15, height = 4, at = vec3(0, y.float, 0), color = eraser)
  if level mod 6 == 3:
    box(vec3(-7, y, 3), vec3(7, y + 3, 10), eraser) # balcony level
  else:
    box(vec3(-1, y + 1, 7), vec3(1, y + 2, 10), eraser) # south window
    box(vec3(-1, y + 1, -10), vec3(1, y + 2, -7), eraser) # north
    box(vec3(7, y + 1, -1), vec3(10, y + 2, 1), eraser) # east
    box(vec3(-10, y + 1, -1), vec3(-7, y + 2, 1), eraser) # west
  y += 5
  level += 1

box(vec3(-1, 1, 7), vec3(1, 4, 10), eraser) # ground-floor doorway
