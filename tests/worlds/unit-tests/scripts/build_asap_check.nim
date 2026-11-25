import testing, builds_private

sleep 1.0 # let the other units load

suite "Scripts finishing":
  test "a script that quits while loading leaves ASAP":
    check not Build(find_by_id("build_quit_at_load")).asap_mode

  test "a script that only draws is shown once it finishes":
    let build = Build(find_by_id("build_draws_only"))
    check not build.asap_mode
    check not build.initializing

  test "an instance that finishes at once leaves ASAP":
    let box = quick_box.new(position = vec3(60, 0, -60))
    sleep 0.5
    check not box.asap_mode

  test "a bot instance walks at the usual speed":
    let walker = quick_walker.new(position = vec3(64, 0, -60))
    check walker.speed == 1.0

  test "a bot instance starts at the turtle":
    drawing = false
    forward 3
    right 2
    let turtle = me.draw_position
    let walker = quick_walker.new
    check walker.position.distance_to(turtle) < 0.01

test_summary()
