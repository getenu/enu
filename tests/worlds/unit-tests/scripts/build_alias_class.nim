import testing

# The file id (build_alias_class) matches `to_thing_id("alias_class")`, so
# this prototype loads under its own name and is never renamed. See
# build_rename_check for the deliberate-mismatch case.
name alias_class(counter = 3)

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
