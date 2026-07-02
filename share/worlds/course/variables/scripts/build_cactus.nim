# Saguaro prototype: every cactus in the canyon is one of these, with its
# own height — the "define once, stamp many" idea the Procedures level
# will teach. (Also our proof that name-protos work in course levels.)
name Cactus(height = 5)
lock = true

if not is_instance:
  show = false
  quit()

speed = 0
color = green
cylinder(1, height) # trunk
cylinder(1, 3, at = vec3(-2, height - 3, 0), color = green) # left arm
box(1, 1, 1, at = vec3(-2, height - 4, 0), color = green)
cylinder(1, 2, at = vec3(2, height - 2, 0), color = green) # right arm
box(1, 1, 1, at = vec3(2, height - 3, 0), color = green)
