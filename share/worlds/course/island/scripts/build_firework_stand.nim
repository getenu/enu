lock = true
speed = 0

# A stout wooden fireworks battery -- a plank deck on legs with a couple
# of dark mortar tubes. Mount a shell on the deck and light it.
color = brown

# four legs
for lx in [0, 4]:
  for lz in [0, 4]:
    box(vec3(lx, 0, lz), vec3(lx, 2, lz), color = brown)

# plank deck
box(vec3(0, 2, 0), vec3(4, 2, 4), color = brown)

# a low back rail so it reads as a rack
box(vec3(0, 3, 0), vec3(4, 4, 0), color = brown)

# two dark mortar tubes flanking the mount
place(1, 3, 1, black)
place(3, 3, 1, black)
