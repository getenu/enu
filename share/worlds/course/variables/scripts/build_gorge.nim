# The gorge floor between the mesas, with a few hoodoo spires.
# (Origin at world (14, 0, -25).)
lock = true
speed = 0
color = brown

box(vec3(-4, 0, 16), vec3(6, 0, -16), color = red) # dry river bed
cylinder(2, 5, at = vec3(-2, 1, 10), color = brown) # hoodoos
cylinder(1, 7, at = vec3(4, 1, 6), color = red)
cylinder(2, 4, at = vec3(1, 1, -9), color = brown)
cylinder(1, 6, at = vec3(5, 1, -13), color = brown)
