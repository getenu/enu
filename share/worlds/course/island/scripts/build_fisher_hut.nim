lock = true
speed = 0

# Weathered fisherman's hut on the south mainland river bank, with a
# tiny jetty poking out over the water. Origin sits on land at world
# (-95, 3, -28); local -z runs downhill toward the water (land holds
# through local z ~ -2..-3, water starts around local z -7).
# A barrel sits east of the door, a drying rack with two hung "fish"
# sits west.

# --- Hut floor + hollow walls (weathered brown) ---
box(vec3(-3, 0, -1), vec3(3, 0, 3), color = brown)             # floor
box(vec3(-3, 1, -1), vec3(3, 3, 3), color = brown, fill = false) # walls

# --- Black tarpaper roof, slight overhang ---
box(vec3(-4, 4, -2), vec3(4, 4, 4), color = black)

# --- Door on the south (land-facing) wall ---
box(vec3(-1, 1, 3), vec3(1, 2, 3), color = eraser)

# --- Windows, east + west ---
place(3, 2, 1, white)
place(-3, 2, 1, white)

# --- Barrel outside, east side ---
cylinder(size = 2, height = 2, at = vec3(5, 0, 1), color = brown)
place(5, 2, 1, black)

# --- Drying rack outside, west side: two posts, a crossbar, two fish ---
place(-5, 0, -1, black)
place(-5, 1, -1, black)
place(-5, 2, -1, black)
place(-5, 0, 1, black)
place(-5, 1, 1, black)
place(-5, 2, 1, black)
box(vec3(-5, 2, -1), vec3(-5, 2, 1), color = black)
place(-5, 1, 0, white)
place(-5, 1, -1, white)

# --- Jetty: planks from the hut's water side out over the strait, on pilings ---
const DECK_Y = 0
box(vec3(-1, DECK_Y, -1), vec3(1, DECK_Y, -11), color = brown)

for z in countup(2, 10):
  if z mod 3 == 0:
    box(vec3(-1, DECK_Y - 1, -z), vec3(-1, DECK_Y - 3, -z), color = brown)
    box(vec3(1, DECK_Y - 1, -z), vec3(1, DECK_Y - 3, -z), color = brown)
