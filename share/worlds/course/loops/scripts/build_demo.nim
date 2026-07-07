# SHOW before tell: a staircase spiral that builds itself with a loop,
# over and over, so the player watches what a loop does before we name it.
# Turtle commands only — exactly what they'll write.
lock = true

forever:
  let start = pen
  speed = 6
  12.times:
    color = cycle(red, white)
    forward 3
    turn 60
    up 1
  sleep 6
  pen = start
  speed = 0
  color = eraser
  12.times:
    forward 3
    turn 60
    up 1
  pen = start
  color = red
  sleep 2
