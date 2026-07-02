# Loops Island: white sand, one step up from the mainland meadow.
# (Local coords are relative to the unit origin at world (0, 0, -10).)
lock = true
speed = 0
color = white

box(vec3(-30, 0, 6), vec3(14, 0, -27), color = white) # main island
box(vec3(40, 0, -10), vec3(54, 0, -30), color = white) # Chest Island
box(vec3(-8, 0, -28), vec3(8, 0, -30), color = white) # sand spit to the rock
box(vec3(-14, 1, -40), vec3(-6, 1, -44), color = brown) # boat dock
