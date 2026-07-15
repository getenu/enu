import testing

speed = 0

suite "swap_color":
  test "recolors drawn blocks and clears the source color":
    color = green
    forward 3
    let spot = me.draw_position
    check block_color_at(spot) == green
    swap_color(green, red)
    check block_color_at(spot) == red
    check block_color_at(spot) != green

  test "recolors to invisible":
    color = green
    up 3
    forward 1
    let spot = me.draw_position
    check block_color_at(spot) == green
    swap_color(green, invisible)
    check block_color_at(spot) == invisible
    # the block still exists (it collides), just renders as nothing
    check has_block_at(spot)

  test "leaves untouched colors alone":
    color = blue
    up 6
    forward 1
    let blue_spot = me.draw_position
    color = green
    forward 2
    swap_color(green, white)
    check block_color_at(blue_spot) == blue

test_summary()
