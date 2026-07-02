# A stranded robot. Rides the ferry; hops off at the far cliff.
lock = true
speed = 1

forever:
  if position.x > 25.5:
    forward 7 .. 10
    turn -60 .. 60
    break
  sleep 0.3
