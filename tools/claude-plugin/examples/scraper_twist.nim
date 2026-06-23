# Turning-torso tower (180 m): a hollow square floor plan rotated a
# little more on every level (0.9 deg/floor = 162 deg total). `pivot =
# centre` keeps each rotated floor centred on the origin; every fourth
# floor banded blue via cycle().
180.times(y):
  box(
    width = 16,
    height = 1,
    depth = 16,
    at = vec3(0, y.float, 0),
    rotation = y.float * 0.9,
    color = cycle(white, white, white, blue),
    fill = false,
    pivot = centre,
  )
