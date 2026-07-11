import testing

name alias_bot(counter = 3)

suite "Class Param Aliasing":
  test "bare param read":
    check counter == 3

  test "bare param write wakes through the setter":
    counter = 5
    check me.counter == 5

  test "param op-assign":
    counter += 2
    check counter == 7

  test "a variable shadows the param":
    var counter = 100
    counter += 1
    check counter == 101
    check me.counter == 7

test_summary()
