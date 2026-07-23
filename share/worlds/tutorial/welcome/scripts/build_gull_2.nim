lock = true
speed = 0

# Gull circling the strait. The flap is a 4-frame animation (down, mid,
# up, mid) played continuously in the background while the script flies
# the circle. All voxels are drawn inside a single chunk (offsets 5..11)
# on purpose: a pose that vacates a chunk leaves a stale mesh there, so
# keeping every frame in one chunk avoids it.

proc body() =
  place(8, 8, 8, white)
  place(8, 8, 9, white)
  place(8, 8, 7, black)

proc wings_down(col: Color) =
  place(7, 8, 8, col); place(6, 7, 8, col); place(5, 7, 8, col)
  place(9, 8, 8, col); place(10, 7, 8, col); place(11, 7, 8, col)

proc wings_mid(col: Color) =
  place(7, 8, 8, col); place(6, 8, 8, col); place(5, 8, 8, col)
  place(9, 8, 8, col); place(10, 8, 8, col); place(11, 8, 8, col)

proc wings_up(col: Color) =
  place(7, 9, 8, col); place(6, 10, 8, col); place(5, 10, 8, col)
  place(9, 9, 8, col); place(10, 10, 8, col); place(11, 10, 8, col)

# the voxels sit at offset (8,8,8) to stay inside one chunk; move the
# rotation pivot there so the bird turns around its body, not the corner
anchor:
  right 8
  up 8
  back 8

place(0, 0, 0, eraser)  # cover the origin default block
clear_frames()
body(); wings_down(white); save()
wings_down(eraser); body(); wings_mid(white); save()
wings_mid(eraser); body(); wings_up(white); save()
wings_up(eraser); body(); wings_mid(white); save()

play(9.0)

move me
speed = 11

let nest = position
forever:
  12.times:
    forward 9
    turn 30.0
  position = nest
