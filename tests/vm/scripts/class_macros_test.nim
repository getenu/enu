# Test class_macros - class definition and property handling
import std/[tables, macros, strutils]
import testing
import types
import core
import base_bridge
import macro_helpers
import class_macros

# Create a test thing and register it as active
var test_thing = Thing()
test_thing.query_results = initTable[string, seq[Thing]]()
register_active(test_thing)

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

  test "command definitions become procs":
    let ast = transform_commands(parse_stmt("- greet(times = 2):\n  echo times"))
    check ast[0].kind == nnkProcDef

  test "commands can be defined inside a block":
    let ast = transform_commands(parse_stmt("block:\n  - greet:\n    echo 1"))
    check ast[0][1][0].kind == nnkProcDef

  test "a negation in an expression isn't a command":
    let ast = transform_commands(parse_stmt("let x = if true: -y else: 1"))
    check "-y" in ast.repr and "proc" notin ast.repr

test_summary()
