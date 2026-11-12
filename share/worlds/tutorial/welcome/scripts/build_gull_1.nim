lock = true
speed = 0

# Gull circling the strait. The flap is a 4-frame animation (down, mid,
# up, mid) of hand-placed blocks, played continuously while the script flies
# the circle. Every pose sits inside a single chunk (offsets 5..11) on
# purpose: a pose that vacates a chunk leaves a stale mesh there.

# the voxels sit at offset (8,8,8) to stay inside one chunk; move the
# rotation pivot there so the bird turns around its body, not the corner
anchor:
  right 8
  up 8
  back 8

play(7.0)

move me
speed = 9

let nest = position
forever:
  15.times:
    forward 12
    turn 24.0
  position = nest
