# Test state_machine loop and transitions
import std/tables
import testing
import state_machine
import base_api
import base_bridge
import types

# Create a test unit and register it as active
var test_unit = Unit()
test_unit.query_results = initTable[string, seq[Unit]]()
register_active(test_unit)

suite "State Machine":
  test "basic loop with counter":
    var basic_counter = 0
    loop:
      inc basic_counter
      if basic_counter >= 5:
        break
    check basic_counter == 5

  test "loop with state transition":
    var visited_states: seq[string] = @[]

    proc state_a() =
      visited_states.add("a")

    proc state_b() =
      visited_states.add("b")

    var transition_counter = 0
    loop:
      inc transition_counter
      nil -> state_a
      if transition_counter >= 2:
        state_a -> state_b
      if transition_counter >= 4:
        state_b -> nil

    check visited_states.len > 0
    check "a" in visited_states
    check "b" in visited_states

  test "immediate transition with ==>":
    var immediate_counter = 0

    proc step_one() =
      inc immediate_counter

    proc step_two() =
      inc immediate_counter

    var loop_counter = 0
    loop:
      inc loop_counter
      nil ==> step_one
      step_one ==> step_two
      step_two ==> nil
      if loop_counter > 10:
        break

    check immediate_counter >= 2

test_summary()
