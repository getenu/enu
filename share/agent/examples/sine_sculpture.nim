import math
# Sine-wave sculpture: rays fanned around the origin, each undulating
# with a sine lean; dashed drawing and rare colour flecks. Leans hard on
# save()/restore() — each ray must start from the saved centre pose.
# Footprint is about twice the ray length in every direction; place it
# with room to breathe.
color = blue

72.times:
  turn 5.0
  save()
  lean back, 20.0
  60.times(i):
    if 1 in 500:
      color = cycle(white, green)
    drawing = 2 in 3
    forward 1
    lean back, sin(i.float * 0.06) * 3.0
  restore()
