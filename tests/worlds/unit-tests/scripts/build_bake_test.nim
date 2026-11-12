import testing

speed = 0

let
  here = me.position
  start_pen = me.pen

proc color_at(offset: Vector3): Color =
  block_color_at(here + offset)

proc raises(body: proc()): bool =
  try:
    body()
  except CatchableError, Defect:
    return true

var
  stamps = 0
  sized_runs = 0
  tries = 0
  painted = 0
  reruns = 0

proc stamp() =
  bake:
    inc stamps
    forward 2

proc sized(n: int) =
  bake n:
    inc sized_runs
    forward n

proc flaky() =
  bake:
    inc tries
    if tries == 1:
      raise ValueError.init("not this time")
    forward 1

proc paint_green() =
  bake:
    inc painted
    color = green

proc redo() =
  rebake "redo":
    inc reruns
    forward 1

proc animation() =
  bake:
    for f in 0 .. 2:
      me.frame = f
      me.draw_voxel(vec3(10, f.float, 0), red)
    me.frame = 0

suite "bake":
  test "the body runs once, and its blocks replay from the turtle":
    me.pen = start_pen
    color = red
    let start = me.draw_position
    for _ in 0 ..< 3:
      stamp()
    check stamps == 1
    let step = (me.draw_position - start) / 6.0
    check step.length > 0.9 and step.length < 1.1
    for k in 1 .. 6:
      check has_block_at(start + step * k.float)

  test "each set of inputs is its own recording":
    me.pen = start_pen
    for n in [1, 2, 1, 2]:
      sized(n)
    check sized_runs == 2

  test "the pen comes back as the body left it":
    me.pen = start_pen
    color = blue
    stamp()
    check color == blue # the body didn't change it
    paint_green()
    color = red
    paint_green()
    check painted == 1
    check color == green

  test "a body that raises isn't kept":
    me.pen = start_pen
    check raises(flaky)
    flaky()
    flaky()
    check tries == 2

  test "a bake can hold every frame of an animation":
    me.pen = start_pen
    me.frames.clear()
    animation()
    me.frames.clear()
    check me.frames.len == 1
    animation()
    check me.frames.len == 3
    check me.frame == 0
    me.frame = 2
    check color_at(vec3(10, 2, 0)) == red
    me.frame = 0
    me.frames.clear()

  test "restructuring frames inside a bake raises":
    check raises(
      proc() =
        bake:
          me.frames.clear()
    )
    check raises(
      proc() =
        bake:
          me.frames[1] = me.frames[0]
    )

  test "two blocks can't share a key":
    proc first() =
      bake "taken":
        forward 1
    proc second() =
      bake "taken":
        forward 1
    me.pen = start_pen
    first()
    check raises(second)

  test "rebake always runs its body":
    me.pen = start_pen
    for _ in 0 ..< 3:
      redo()
    check reruns == 3

  test "clear_bakes forgets every recording":
    me.pen = start_pen
    stamp()
    let before = stamps
    me.clear_bakes()
    stamp()
    check stamps == before + 1

test_summary()
