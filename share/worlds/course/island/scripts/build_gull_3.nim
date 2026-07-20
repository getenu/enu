lock = true
speed = 0

# Gull circling the sky just north of the spawn, so birds drift through the
# opening view after a moment. Same 4-frame flap as the other gulls; all
# voxels sit inside one chunk (offsets 5..11) so a pose that vacates a chunk
# never leaves a stale mesh behind.

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

play(8.0)

move me
speed = 8

let nest = position
forever:
  14.times:
    forward 10
    turn 26.0
  position = nest
