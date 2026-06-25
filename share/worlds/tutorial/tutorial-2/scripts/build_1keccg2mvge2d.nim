import math

speed = 0
scale = 0.6

360.times:
  turn 1
  save()
  lean back, 20
  200.times(i):
    if 1 in 500:
      color = cycle(white, green)
    else:
      color = black
    drawing = 2 in 3
    forward 1
    lean back, sin(i * 0.06) * 3.0
  restore()

# Now that we've finished building we move it into position.
move me
speed = 100
up 101
lean 179

# turn and scale
speed = 50
var counter = 0
forever:
  counter = counter + 1
  scale = 0.6 + sin(counter * 0.05) * 0.03
  turn right, 0.1
