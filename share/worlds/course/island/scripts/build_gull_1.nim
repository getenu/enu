lock = true
speed = 0

# Gull circling the strait. Wing flap is a 4-frame animation (down, mid,
# up, mid) played continuously in the background; the script only flies
# the circle. Drawing while playback runs raises, so all frame authoring
# happens before play().

proc body() =
  place(0, 0, 0, white)
  place(0, 0, 1, white)
  place(0, 0, -1, black)

proc wings_down(col: Color) =
  place(-1, 0, 0, col)
  place(-2, -1, 0, col)
  place(-3, -1, 0, col)
  place(1, 0, 0, col)
  place(2, -1, 0, col)
  place(3, -1, 0, col)

proc wings_mid(col: Color) =
  place(-1, 0, 0, col)
  place(-2, 0, 0, col)
  place(-3, 0, 0, col)
  place(1, 0, 0, col)
  place(2, 0, 0, col)
  place(3, 0, 0, col)

proc wings_up(col: Color) =
  place(-1, 1, 0, col)
  place(-2, 2, 0, col)
  place(-3, 2, 0, col)
  place(1, 1, 0, col)
  place(2, 2, 0, col)
  place(3, 2, 0, col)

clear_frames()
body()
wings_down(white)
save()
wings_down(eraser)
body()
wings_mid(white)
save()
wings_mid(eraser)
body()
wings_up(white)
save()
wings_up(eraser)
body()
wings_mid(white)
save()

play(7.0)

move me
speed = 7

# the glide segments accumulate drift, so re-centre after each lap
let nest = position
forever:
  18.times:
    forward 18
    turn 20.0
  position = nest
