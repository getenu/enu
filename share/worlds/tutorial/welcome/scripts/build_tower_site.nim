speed = 5

color = brown

# Lookout tower -- start: a 3x3 ring, two layers up.
2.times:
  4.times:
    forward 2
    turn right
  up 1

# The lookout needs to reach 12 high to see over the palms!
# hint: `4.times:` repeats what's under it four times
# hint: `up 1` climbs one block before the next layer
