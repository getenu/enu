# Bubble tower (~140 m): overlapping spheres climbing a column. The first
# sphere is centred AT ground level so the ground floor is a dome; a wide
# eraser shaft turns every orb into a round room; portholes are punched
# through each shell; a doorway opens the dome.
let h = 132
var y = 9 # first sphere centre at ~radius height, so it sits on the ground
while y <= h:
  let d = 24 + (0 .. 6)
  sphere(size = d, at = vec3(0, y.float, 0), color = cycle(blue, white))
  let r = d.float / 2.0
  sphere(size = 5, at = vec3(r, y.float + 1.0, 0), color = eraser)
  sphere(size = 5, at = vec3(-r, y.float + 1.0, 0), color = eraser)
  sphere(size = 5, at = vec3(0, y.float + 1.0, r), color = eraser)
  sphere(size = 5, at = vec3(0, y.float + 1.0, -r), color = eraser)
  y += 11

sphere(size = 13, at = vec3(0, (h + 9).float, 0), color = white) # cap
cylinder(size = 13, height = h + 9, at = vec3(0, 1, 0), color = eraser) # core
box(vec3(-2, 1, 8), vec3(2, 5, 13), eraser) # dome doorway
