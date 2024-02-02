name tower(height = 70, length = 20, sides = 4, twist = 0)
speed = 0
height.times:
  sides.times:
    forward length
    turn 360 / sides + twist
  up 1
