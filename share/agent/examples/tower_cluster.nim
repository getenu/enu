# Spawner for Tower (see tower.nim): walk a wandering path, dropping a
# randomly-parameterised instance at each stop — a little city of twisty
# towers, each different. `seed` makes the layout reproducible.
drawing = false
seed = 11

turn right
8.times:
  forward 12 .. 20
  turn 25 .. 65
  Tower.new(
    height = 28 .. 52,
    sides = 3 .. 8,
    length = 5 .. 9,
    twist = -3.0 .. 3.0,
    color = cycle(red, green, blue, white, brown),
  )
