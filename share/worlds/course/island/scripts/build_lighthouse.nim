lock = true
speed = 0
import math

# Coastal lighthouse: white tapered tower with a bold red barber-pole
# spiral, a stone plinth sunk into the sloping headland, a door facing the
# land path (west), and an open lamp-room cage under a small black roof so
# the lamp inside shines out to the strait and the island.

# --- Stone plinth (sunk into the slope; low side is toward the water) ---
cylinder(size = 11, height = 1, at = vec3(0, -2, 0), color = brown)
cylinder(size = 10, height = 1, at = vec3(0, -1, 0), color = brown)
cylinder(size = 9, height = 1, at = vec3(0, 0, 0), color = brown)

# --- Tower body: white, tapering from d=7 at the base to d~5.5 at the top ---
const BODY_TOP = 13
for y in 1 .. BODY_TOP:
  let d = 7.0 - (y - 1).float * (1.6 / (BODY_TOP - 1).float)
  cylinder(size = d, height = 1, at = vec3(0, y, 0), color = white)

# --- Red barber-pole spiral painted onto the body surface ---
for y in 1 .. BODY_TOP:
  let d = 7.0 - (y - 1).float * (1.6 / (BODY_TOP - 1).float)
  let r = d / 2.0 - 0.4
  let centre = y.float * 46.0 * PI / 180.0   # spiral pitch per layer
  var a = -50.0
  while a <= 50.0:                            # ~100 deg red arc, rest white
    let ang = centre + a * PI / 180.0
    let x = round(r * cos(ang)).int
    let z = round(r * sin(ang)).int
    place(x, y, z, red)
    a += 6.0

# --- Door on the west face (toward the land path), white frame ---
box(vec3(-3, 1, -1), vec3(-2, 3, 1), color = eraser)  # carve opening
place(-3, 4, -1, white)                               # lintel
place(-3, 4, 0, white)
place(-3, 4, 1, white)
for yy in 1 .. 3:
  place(-3, yy, -2, white)                            # jambs
  place(-3, yy, 2, white)

# --- A couple of small windows up the shaft (toward the sea) ---
place(0, 6, 3, white)
place(0, 10, 3, white)

# --- Gallery: white walkway ring overhanging the body top ---
cylinder(size = 8, height = 1, at = vec3(0, BODY_TOP + 1, 0), color = white)
# red trim lip around the gallery edge
block:
  let r = 3.6
  var a = 0.0
  while a < 360.0:
    let ang = a * PI / 180.0
    place(round(r * cos(ang)).int, BODY_TOP + 1, round(r * sin(ang)).int, red)
    a += 8.0

# --- Lamp-room cage: open black framework so the lamp shows through ---
const CAGE_BASE = BODY_TOP + 2      # 15
const CAGE_TOP = CAGE_BASE + 3      # 18  (4-tall open viewing band)
let post_r = 3.0
# eight slender corner posts, tall and well spaced for wide open windows
var pa = 0.0
while pa < 360.0:
  let ang = pa * PI / 180.0
  let px = round(post_r * cos(ang)).int
  let pz = round(post_r * sin(ang)).int
  for y in CAGE_BASE .. CAGE_TOP:
    place(px, y, pz, black)
  pa += 45.0
# thin top frame ring tying the posts together
var ta = 0.0
while ta < 360.0:
  let ang = ta * PI / 180.0
  place(round(post_r * cos(ang)).int, CAGE_TOP, round(post_r * sin(ang)).int, black)
  ta += 10.0

# --- Small roof: black cap narrowing to a point ---
cylinder(size = 8, height = 1, at = vec3(0, CAGE_TOP + 1, 0), color = black)
cylinder(size = 5, height = 1, at = vec3(0, CAGE_TOP + 2, 0), color = black)
place(0, CAGE_TOP + 3, 0, black)
