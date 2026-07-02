# The causeway + pier behind the gate: where the next level will start.
lock = true
speed = 0
color = brown
box(vec3(-2, 0, 6), vec3(2, 0, -8), color = brown) # causeway through the gate
box(vec3(-6, 0, -8), vec3(6, 0, -14), color = brown) # pier platform

up 2
forward 10
say "- Next stop: Variables!",
  """
  # Next stop: **Variables**

  (The ferry to the next island isn't running yet —
  this is where the course continues.)
  """,
  width = 3.0
