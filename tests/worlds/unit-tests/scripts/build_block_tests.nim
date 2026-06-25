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

test_summary()
