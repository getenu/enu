import unittest2
import std/[os, sequtils]
import core
import libs/interpreters

const script_dir = "tests/unit/scripts"

suite "Interpreter":
  var interp: Interpreter

  setup:
    interp = Interpreter.init(script_dir, "vmlib")

  test "load and run simple script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load("test.nim", """
let x* = 42
let msg* = "hello"
""")
    let continued = ctx.run()
    check not continued
    check ctx.exit_code.is_none

  test "get integer variable from script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load("test2.nim", """
let answer* = 123
""")
    discard ctx.run()
    let val = ctx.get_var("answer", "test2")
    check val.int_val == 123

  test "get string variable from script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load("test3.nim", """
let greeting* = "hello world"
""")
    discard ctx.run()
    let val = ctx.get_var("greeting", "test3")
    check val.str_val == "hello world"

  test "multiple scripts can run on same interpreter":
    var ctx1 = ScriptCtx(interpreter: interp)
    ctx1.load("multi1.nim", """
let value1* = 100
""")
    discard ctx1.run()

    var ctx2 = ScriptCtx(interpreter: interp)
    ctx2.load("multi2.nim", """
let value2* = 200
""")
    discard ctx2.run()

    check ctx1.get_var("value1", "multi1").int_val == 100
    check ctx2.get_var("value2", "multi2").int_val == 200
