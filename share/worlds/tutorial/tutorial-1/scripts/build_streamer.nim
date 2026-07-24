name Streamer(speed = 0.2, count = 99)
if not is_instance:
  show = false
  quit()

lean back
var base_speed = speed

count.times:
  if 1 in 3:
    speed = base_speed
    color = random(green, black, blue, white, red, green, white, green)

    drawing = true
    back 3
    left 1
    forward 3
  else:
    drawing = false
    speed = 0
    forward 2
  forward 1 .. 4
  turn -35 .. 35
  lean -45 .. 35
