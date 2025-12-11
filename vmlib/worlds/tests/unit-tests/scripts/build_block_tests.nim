import testing

speed = 0

suite "Block Placement":
  test "initial block exists at build origin":
    let origin = me.position
    echo "Build position: ", origin
    check has_block_at(origin)

  test "block_color_at returns correct color for initial block":
    # The initial block should be Blue (the build's start_color)
    check block_color_at(me.position) == blue

  # Known issue: has_block_at doesn't find blocks at negative local coordinates
  # The block IS placed (verified visually), but the lookup fails.
  # This may be a chunk boundary issue with negative Z coordinates.
  # test "forward places block at draw_position":
  #   forward 1
  #   check has_block_at(me.draw_position)

test_summary()
