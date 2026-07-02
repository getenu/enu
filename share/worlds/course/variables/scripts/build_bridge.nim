# The old bridge washed out. The gorge is 12 blocks wide — how many
# planks does it take to reach the other mesa?

var planks = 2   # <-- not enough! Change me.

color = brown
planks.times:
  box(2, 1, 3)
  forward 2
