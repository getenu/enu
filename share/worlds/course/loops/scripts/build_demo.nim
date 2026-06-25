# SHOW before tell: this staircase builds ITSELF with a loop, so the
# player watches what a loop does before we ever name it. Turtle commands
# only (forward / turn / up) — exactly how they'll build.
color = cycle(red, white)
speed = 4 # draw slowly enough to watch it climb

24.times:
  forward 4
  turn 30
  up 1
