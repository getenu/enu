name maze(building = true)

speed = 0
seed = 1

var
  angle = 0.0
  primary_color = black
  roof_odds = 6
  roof_sides = {2, 3}

- ring:
  5.times(side):
    color = if 1 in 20:
      cycle(blue, red, green, black, white, brown)
    else:
      primary_color
    drawing = 1 in roof_odds or side notin roof_sides
    forward 10
    lean back, 360 / 5
  turn angle
  left 0.5

turn left
2000.times:
  ring()
  if 1 in 50:
    angle = -2.0..1.0
    if 1 in 3:
      primary_color = cycle(black, white, black)
    else:
      if 1 in 2:
        roof_odds = 2..5
      elif 1 in 2:
        roof_odds = 1
      if 1 in 4:
        roof_sides = {1, 2, 3, 4}
      else:
        roof_sides = {2, 3}

building = false
