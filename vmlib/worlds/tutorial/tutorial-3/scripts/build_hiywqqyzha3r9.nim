name Door(color = green, open = false, width = 20, height = 11)

speed = 0
height.times:
  right width
  turn 180
  up 1

move me
scale = 1.05
forward 0.05
speed = 5

loop:
  nil -> sleep as door_closed
  if open:
    door_closed -> left(home + width) as door_open
  else:
    door_open -> right(home) as door_closed
