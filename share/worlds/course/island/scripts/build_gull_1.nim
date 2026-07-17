lock = true
speed = 0

# Small white gull circling the strait. Body + two 3-voxel wings; the
# wings alternate between a flat and a raised pose each loop step by
# repainting voxels at runtime (root units can repaint; proto instances
# can't — see the level CLAUDE.md corrections).

place(0, 0, 0, white)   # body
place(0, 0, 1, white)   # tail
place(0, 0, -1, black)  # beak

proc wings_flat(col: Color) =
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

wings_flat(white)

move me
speed = 7

var wing_up = false

forever:
  if wing_up:
    wings_flat(eraser)
    wings_up(white)
  else:
    wings_up(eraser)
    wings_flat(white)
  wing_up = not wing_up
  forward 5.2
  turn left, 20.0
