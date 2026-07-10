import testing

speed = 0

suite "Block Placement":
  test "initial block exists at build origin":
    check has_block_at(me.position)

  test "block_color_at returns correct color for initial block":
    check block_color_at(me.position) == blue

  test "forward places block at draw_position":
    forward 1
    check has_block_at(me.draw_position)

suite "Pen":
  test "pen round-trips pose, color and drawing":
    color = red
    forward 2
    up 1
    let spot = pen
    color = white
    drawing = false
    forward 5
    turn 90
    pen = spot
    check me.color == red
    check drawing == true
    check me.draw_position == spot.position.origin + me.position

  test "pen captures independent snapshots":
    let first = pen
    forward 3
    let second = pen
    check first.position.origin != second.position.origin
    pen = first
    check me.draw_position == first.position.origin + me.position

test_summary()
