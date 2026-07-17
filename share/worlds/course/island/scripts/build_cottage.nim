speed = 0

# A weathered stone-and-timber cottage. A storm punched a hole clean
# through the east wall -- the side you walk up on.

# stone foundation (also buries the default block at 0,0,0 and evens the slope)
box(vec3(0, 0, 0), vec3(8, 0, 6), color = white)

# --- stone walls, 4 courses high (local y1..y4) ---
box(vec3(0, 1, 0), vec3(8, 4, 0), color = white)   # north wall
box(vec3(0, 1, 6), vec3(8, 4, 6), color = white)   # south wall
box(vec3(0, 1, 0), vec3(0, 4, 6), color = white)   # west wall

# east wall -- the storm-damaged side. Two intact ends with a ragged
# breach torn out of the middle (the clean core is z2..4, y1..4).
box(vec3(8, 1, 0), vec3(8, 4, 1), color = white)   # north end (z0..1)
box(vec3(8, 1, 5), vec3(8, 4, 6), color = white)   # south end (z5..6)
# jagged storm-torn edges, nibbled just outside the main breach
place(8, 4, 1, eraser)
place(8, 1, 1, eraser)
place(8, 4, 5, eraser)
place(8, 3, 5, eraser)

# --- timber corner posts ---
box(vec3(0, 1, 0), vec3(0, 4, 0), color = brown)
box(vec3(8, 1, 0), vec3(8, 4, 0), color = brown)
box(vec3(0, 1, 6), vec3(0, 4, 6), color = brown)
box(vec3(8, 1, 6), vec3(8, 4, 6), color = brown)

# --- doorway in the south wall (that one's meant to be open) ---
box(vec3(3, 1, 6), vec3(4, 3, 6), color = eraser)

# --- pitched hip roof (red tiles, brown ridge beam), local y5..y8 ---
box(vec3(-1, 5, 0), vec3(9, 5, 6), color = red)    # eave course (overhang)
box(vec3(0, 6, 1), vec3(8, 6, 5), color = red)
box(vec3(1, 7, 2), vec3(7, 7, 4), color = red)
box(vec3(2, 8, 3), vec3(6, 8, 3), color = brown)   # ridge beam

# --- tumbled stones knocked loose on the ground outside the breach ---
place(9, 0, 2, white)
place(10, 0, 3, white)
place(9, 0, 4, brown)
place(11, 0, 3, white)
place(10, 1, 3, white)

# Storm damage! Patch the hole in the wall.
# hint: you can place blocks by hand with the block tools...
# hint: ...or draw them with code: `box(vec3(...), vec3(...), color = white)`
