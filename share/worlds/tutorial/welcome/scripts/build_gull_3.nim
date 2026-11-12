lock = true
speed = 0

# Gull circling the sky just north of the spawn, so birds drift through the
# opening view after a moment. Same hand-placed 4-frame flap as the other
# gulls; every pose sits inside one chunk (offsets 5..11) so a pose that
# vacates a chunk never leaves a stale mesh behind.

anchor:
  right 8
  up 8
  back 8

play(8.0)

move me
speed = 8

let nest = position
forever:
  14.times:
    forward 10
    turn 26.0
  position = nest
