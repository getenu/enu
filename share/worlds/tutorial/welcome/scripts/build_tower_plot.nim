lock = true
speed = 0

# Construction plot for the lookout tower. Static plaza + corner markers
# hinting at what's meant to rise here — the actual tower goes in the
# player-editable build_tower_site next door (keep clear of it).

place(0, 0, 0, eraser) # erase the default block; plaza sits west of here

box(vec3(-7, 0, -3), vec3(-1, 0, 3), color = black)

place(-7, 0, -3, white)
place(-7, 0, 3, white)
place(-1, 0, -3, white)
place(-1, 0, 3, white)

# faint corner pillars — something tall goes here
place(-7, 1, -3, black)
place(-7, 2, -3, black)
place(-7, 1, 3, black)
place(-7, 2, 3, black)
place(-1, 1, -3, black)
place(-1, 2, -3, black)
place(-1, 1, 3, black)
place(-1, 2, 3, black)

# surveyor's post + tiny flag
place(-4, 1, -1, brown)
place(-4, 2, -1, brown)
place(-3, 2, -1, red)
