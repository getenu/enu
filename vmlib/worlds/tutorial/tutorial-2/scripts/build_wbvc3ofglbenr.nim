drawing = false
seed = 213
speed = 0
turn right
10.times:
  forward 20 .. 40
  turn 20 .. 50
  tower.new(
    height = 40 .. 100,
    length = 5 .. 10,
    sides = 3 .. 10,
    twist = -2 .. 2,
    color = cycle(red, green, blue, black),
  )
