# Switchback terraces from the meadow up to the town mesa — every step is
# one block, so anyone (and any bot) can walk up. (Origin world (0, 0, -8).)
lock = true
speed = 0
color = brown

box(vec3(-3, 0, 4), vec3(3, 0, 0), color = brown) # step 1
box(vec3(-3, 1, 2), vec3(3, 1, -1), color = red) # step 2
box(vec3(-3, 2, 0), vec3(3, 2, -2), color = brown) # step 3
