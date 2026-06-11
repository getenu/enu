import unittest2
import std/[os, sequtils, importutils, strutils]
import pkg/compiler/[vmdef, lineinfos]
from pkg/compiler/options import ConfigRef
import core
import libs/[interpreters, eval]

const script_dir = "tests/unit/scripts"

suite "Interpreter":
  var interp: Interpreter

  setup:
    interp = Interpreter.init(script_dir, "vmlib")

  test "load and run simple script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load(
      "test.nim", """
let x* = 42
let msg* = "hello"
"""
    )
    let continued = ctx.run()
    check not continued
    check ctx.exit_code.is_none

  test "get integer variable from script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load(
      "test2.nim", """
let answer* = 123
"""
    )
    discard ctx.run()
    let val = ctx.get_var("answer", "test2")
    check val.int_val == 123

  test "get string variable from script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load(
      "test3.nim", """
let greeting* = "hello world"
"""
    )
    discard ctx.run()
    let val = ctx.get_var("greeting", "test3")
    check val.str_val == "hello world"

  test "multiple scripts can run on same interpreter":
    var ctx1 = ScriptCtx(interpreter: interp)
    ctx1.load(
      "multi1.nim", """
let value1* = 100
"""
    )
    discard ctx1.run()

    var ctx2 = ScriptCtx(interpreter: interp)
    ctx2.load(
      "multi2.nim", """
let value2* = 200
"""
    )
    discard ctx2.run()

    check ctx1.get_var("value1", "multi1").int_val == 100
    check ctx2.get_var("value2", "multi2").int_val == 200

  test "call depth budget is per script, not shared across parked scripts":
    # The VM call-depth counter is a single countdown on the shared PCtx.
    # Scripts that yield park their stacks mid-call and used to hold their
    # decrements against every other script, so enough parked scripts made
    # any further call fail with "maximum call depth for the VM exceeded".
    private_access ScriptCtx

    interp.config.max_call_depth_vm = 100

    const pause_line = 3 # `result = 1`, only reached at the recursion floor
    const script_a = """
proc work_a(n: int): int =
  if n == 0:
    result = 1
  else:
    result = work_a(n - 1)

let ra* = work_a(60)
"""
    const script_b = """
proc work_b(n: int): int =
  if n == 0:
    result = 1
  else:
    result = work_b(n - 1)

var rb* = work_b(20)
rb += work_b(55)
rb += work_b(65)
"""

    var current: ScriptCtx
    var armed = false
    interp.enter_hook = proc(
        c: PCtx, pc: int, tos: PStackFrame, instr: TInstr
    ) =
      current.ctx = c
      current.pc = pc
      current.tos = tos
      if armed:
        let info = c.debug[pc]
        let file =
          interp.config.m.file_infos[info.file_index.int].full_path.string
        if info.line.int == pause_line and
            file.ends_with(current.module_name & ".nim"):
          armed = false
          raise VMPause.new_exception("vm paused")

    interp.register_error_hook proc(
        config, info, msg, severity: auto
    ) {.gcsafe.} =
      if severity == Severity.Error and config.error_counter >= config.error_max:
        raise (ref VMQuit)(info: info, msg: msg)

    # Module loads reset the counter (vm refresh), so the bug only bites on
    # resumes: park b shallow, park a deep, then resume b through two calls
    # that each need more budget than the other scripts left behind.
    var ctx_b = ScriptCtx(interpreter: interp)
    current = ctx_b
    armed = true
    ctx_b.load("parked_b.nim", script_b)
    check ctx_b.run() # parks at depth ~21

    var ctx_a = ScriptCtx(interpreter: interp)
    current = ctx_a
    armed = true
    ctx_a.load("parked_a.nim", script_a)
    check ctx_a.run() # parks at depth ~61

    current = ctx_b
    armed = true
    check ctx_b.resume() # work_b(55) parks at ~56
    armed = true
    check ctx_b.resume() # work_b(65) used to exhaust the shared budget
    check not ctx_b.resume() # completes

    current = ctx_a
    check not ctx_a.resume()
    check ctx_a.get_var("ra", "parked_a").int_val == 1
    check ctx_b.get_var("rb", "parked_b").int_val == 3
