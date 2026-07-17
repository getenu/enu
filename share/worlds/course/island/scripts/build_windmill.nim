lock = true
speed = 0

# --- Foundation footing at the waterline (a touch wider than the body) ---
cylinder(size = 8, height = 1, at = vec3(0, 0, 0), color = brown)

# --- Tower body: stout tapered brown, 7 wide at the base -> ~5 near the top ---
for y in 1 .. 8:
  let d = 7.0 - (y - 1).float * (2.0 / 7.0)
  cylinder(size = d, height = 1, at = vec3(0, y, 0), color = brown)

# --- White gallery band under the cap ---
cylinder(size = 5.6, height = 1, at = vec3(0, 8, 0), color = white)

# --- Cap: brown dome overhanging the gallery, narrowing to a point ---
cylinder(size = 6, height = 1, at = vec3(0, 9, 0), color = brown)
cylinder(size = 4, height = 1, at = vec3(0, 10, 0), color = brown)
cylinder(size = 2, height = 1, at = vec3(0, 11, 0), color = brown)

# --- Door on the south face, with a white frame ---
box(vec3(-1, 1, 2), vec3(1, 3, 4), color = eraser)   # carve the doorway
box(vec3(-2, 4, 3), vec3(2, 4, 3), color = white)     # lintel
for yy in 1 .. 3:
  place(-2, yy, 3, white)                              # left jamb
  place(2, yy, 3, white)                               # right jamb

# --- Small windows (white) ---
place(0, 6, 3, white)      # south
place(3, 5, 0, white)      # east
place(-3, 5, 0, white)     # west
