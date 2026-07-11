import testing

# A top-level variable named after a property claims the name for the
# whole script. `glow` below always means this variable; the engine
# property is still reachable as `me.glow`.
var glow = 5.0

suite "Property Aliasing":
  test "bare property write hits the engine":
    speed = 3
    check me.speed == 3

  test "bare property read":
    check speed == 3

  test "op-assign goes through the accessor":
    speed += 2
    check me.speed == 5

  test "a variable shadows the property in its scope":
    var speed = 100.0
    speed += 1
    check speed == 101.0
    check me.speed == 5

  test "shadowing ends with the scope":
    speed = 7
    check me.speed == 7

  test "top-level alias wins for the whole script":
    glow += 1
    check glow == 6.0
    check me.glow != 6.0

test_summary()
