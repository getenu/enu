# Dusty's water tower fell down! The legs are way too short.
# Fix ONE number so the tank lines up with the white ring.

var height = 2   # <-- this number is the legs' height. Change me!

color = brown
box(1, height, 1, at = vec3(0, 0, 0))
box(1, height, 1, at = vec3(4, 0, 0))
box(1, height, 1, at = vec3(0, 0, -4))
box(1, height, 1, at = vec3(4, 0, -4))
color = red
box(5, 2, 5, at = vec3(0, height, 0)) # the tank sits on the legs
