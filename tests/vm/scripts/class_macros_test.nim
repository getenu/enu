# Test class_macros - class definition and property handling
import std/[tables, macros]
import testing
import types
import base_api
import base_bridge
import macro_helpers

# Create a test unit and register it as active
var test_unit = Unit()
test_unit.query_results = initTable[string, seq[Unit]]()
register_active(test_unit)

suite "Class Macros":
  test "parse_sig with simple function":
    # parse_sig returns (name: string, params: seq[NimNode], vars: NimNode)
    let (name1, params1, vars1) = parse_sig(quote do: my_func)
    check name1 == "my_func"
    check params1.len == 1  # just return type

  test "parse_sig with parameters":
    let (name2, params2, vars2) = parse_sig(quote do: my_func(x = 5))
    check name2 == "my_func"
    # params includes return type + function params
    check params2.len == 2

  test "parse_sig with typed parameter":
    let (name3, params3, vars3) = parse_sig(quote do: my_func(x: int))
    check name3 == "my_func"
    check params3.len == 2

  test "parse_sig with multiple parameters":
    let (name4, params4, vars4) = parse_sig(quote do: my_func(x = 1, y = 2))
    check name4 == "my_func"
    check params4.len == 3  # return type + 2 params

test_summary()
