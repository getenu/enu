# The sea: a calm blue shelf around the island, plus the channel that
# separates Salty from Chest Island. Everything is 1 block thick, sitting
# on the world plane, so nobody can fall anywhere they can't walk out of.
# (Local coords are relative to the unit origin at world (0, 0, -50).)
lock = true
speed = 0
color = blue

box(vec3(-52, 0, 12), vec3(54, 0, -30), color = blue) # open sea, north
box(vec3(15, 0, 32), vec3(39, 0, 6), color = blue) # Salty's channel, east
