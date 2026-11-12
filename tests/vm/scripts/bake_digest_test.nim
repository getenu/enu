# What makes a `bake` block's key. The runner's mock bake cache skips a body
# whose key it has seen, and never skips a `rebake`.
import testing
import builds

var runs = 0

proc stamp() =
  bake:
    inc runs

proc named() =
  bake "shared-key":
    inc runs

suite "bake keys":
  test "a block replays every time it's reached after the first":
    runs = 0
    for _ in 0 ..< 3:
      stamp()
    check runs == 1

  test "two blocks with the same code are separate recordings":
    runs = 0
    bake:
      inc runs
    bake:
      inc runs
    check runs == 2

  test "a keyed block is its key":
    runs = 0
    for _ in 0 ..< 3:
      named()
    check runs == 1

  test "inputs are part of the key":
    runs = 0
    for n in [1, 2, 1, 2]:
      bake n:
        runs += n * 0 + 1
    check runs == 2

  test "a key before the inputs":
    runs = 0
    for n in [1, 2, 1]:
      bake "sized", n:
        runs += n * 0 + 1
    check runs == 2

  test "rebake always runs":
    runs = 0
    for _ in 0 ..< 3:
      rebake:
        inc runs
    check runs == 3

test_summary()
