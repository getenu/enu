lock = true

# The peninsula landing pad + castaways' camp. A twin of the island pad,
# but this one is a pier reaching from the shore out over the shallows so
# the ferry can berth. The camp deck runs back toward solid ground, and
# that's where the rescued castaways settle.

glow = 0.3   # the warm flicker of the campfire, out on the shore at dusk

# ----- the 5x5 landing pad (pier head), skirted down to the waterline -----
box(vec3(-2, -1, -2), vec3(2, 1, 2), color = brown)

# white corner markers -- the same posts as the island pad, to read as a pair
for cx in [-2, 2]:
  for cz in [-2, 2]:
    box(vec3(cx, 2, cz), vec3(cx, 4, cz), color = white)

# ----- camp deck: solid planking running west back toward the shore -----
box(vec3(-9, -1, -2), vec3(-2, 1, 2), color = brown)

# ----- campfire ring out on the camp deck -----
# black stones ringing a red fire; the whole build glows softly (above)
place(-8, 2, 0, black)
place(-6, 2, 0, black)
place(-7, 2, -1, black)
place(-7, 2, 1, black)
place(-7, 2, 0, red)   # the fire itself

# ----- two logs to sit on, either side of the fire -----
box(vec3(-8, 2, 2), vec3(-6, 2, 2), color = brown)
box(vec3(-8, 2, -2), vec3(-6, 2, -2), color = brown)

# ----- a lean-to shelter at the back of the camp -----
# two upright posts at the open front, a back wall, and a sloping roof
box(vec3(-9, 2, -2), vec3(-9, 4, -2), color = brown)   # front post
box(vec3(-9, 2, 2), vec3(-9, 4, 2), color = brown)     # front post
box(vec3(-9, 2, -2), vec3(-9, 3, 2), color = brown)    # back wall (low)
box(vec3(-9, 4, -2), vec3(-8, 4, 2), color = brown)    # roof, high edge
box(vec3(-8, 3, -2), vec3(-7, 3, 2), color = brown)    # roof, low edge
