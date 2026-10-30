import unittest2
import std/[os, sequtils, importutils, strutils]
import pkg/compiler/ast except new_node
import pkg/compiler/[vmdef, lineinfos]
from pkg/compiler/options import ConfigRef
import core
import libs/[interpreters, eval]

private_access ScriptCtx

proc to_node(n: PNode): PNode = n # for call_proc's varargs

# Scripts park through host calls, which the VM matches by package, so they
# live in a scratch package.
let script_dir = get_temp_dir() / "enu_script_ctx_test"
create_dir script_dir
write_file script_dir / "enu_script_ctx_test.nimble", ""
write_file script_dir / "host.nim", "proc park*() = discard\n"
const fuel = 5_000_000

suite "Interpreter":
  var interp: Interpreter

  setup:
    interp = Interpreter.init(script_dir, "share/vmlib", fuel)

  test "load and run simple script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load(
      "test.nim", """
let x* = 42
let msg* = "hello"
"""
    )
    let continued = ctx.run(0)
    check not continued
    check ctx.exit_code.is_none

  test "get integer variable from script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load(
      "test2.nim", """
let answer* = 123
"""
    )
    discard ctx.run(0)
    let val = ctx.get_var("answer", "test2")
    check val.int_val == 123

  test "get string variable from script":
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load(
      "test3.nim", """
let greeting* = "hello world"
"""
    )
    discard ctx.run(0)
    let val = ctx.get_var("greeting", "test3")
    check val.str_val == "hello world"

  test "multiple scripts can run on same interpreter":
    var ctx1 = ScriptCtx(interpreter: interp)
    ctx1.load(
      "multi1.nim", """
let value1* = 100
"""
    )
    discard ctx1.run(0)

    var ctx2 = ScriptCtx(interpreter: interp)
    ctx2.load(
      "multi2.nim", """
let value2* = 200
"""
    )
    discard ctx2.run(0)

    check ctx1.get_var("value1", "multi1").int_val == 100
    check ctx2.get_var("value2", "multi2").int_val == 200

  test "call depth budget is per script, not shared across parked scripts":
    # The VM's call-depth counter lives on the shared PCtx. Scripts park their
    # stacks mid-call; each must get its own budget or enough parked scripts
    # make any further call fail with "maximum call depth for the VM
    # exceeded".
    interp.config.max_call_depth_vm = 100

    const script_a = """
import host
proc work_a(n: int): int =
  if n == 0:
    park()
    result = 1
  else:
    result = work_a(n - 1)

proc run_a*(): int = work_a(60)
"""
    const script_b = """
import host
proc work_b(n: int): int =
  if n == 0:
    park()
    result = 1
  else:
    result = work_b(n - 1)

proc run_b*(): int =
  result = work_b(20)
  result += work_b(55)
  result += work_b(65)
"""

    var current: ScriptCtx
    interp.implement_routine "enu_script_ctx_test", "host", "park",
      proc(a: VmArgs) {.gcsafe.} =
        {.gcsafe.}:
          current.pause()
          current.after_host_call()

    interp.register_error_hook proc(
        config, info, msg, severity: auto
    ) {.gcsafe.} =
      if severity == Severity.Error and config.error_counter >= config.error_max:
        raise (ref VMQuit)(info: info, msg: msg)

    var ctx_b = ScriptCtx(interpreter: interp)
    current = ctx_b
    ctx_b.load(script_dir / "parked_b.nim", script_b)
    check not ctx_b.run(0)
    check ctx_b.call_proc("run_b").paused # parks at depth ~21

    var ctx_a = ScriptCtx(interpreter: interp)
    current = ctx_a
    ctx_a.load(script_dir / "parked_a.nim", script_a)
    check not ctx_a.run(0)
    check ctx_a.call_proc("run_a").paused # parks at depth ~61

    current = ctx_b
    check ctx_b.resume() # work_b(55) parks at ~56
    check ctx_b.resume() # work_b(65) parks at ~66
    check not ctx_b.resume() # completes

    current = ctx_a
    check not ctx_a.resume()

  test "parked scripts keep their own frames":
    # Scripts park mid-call and resume in any order; each has its own VM
    # stack, so interleaving them can't clobber the others' locals.
    const script = """
import host
proc walk(depth, seed: int): int =
  var s = "s" & $depth
  park()
  if depth > 0:
    result = walk(depth - 1, seed) + s.len
  else:
    result = seed
  park()

var last_total* = 0
proc total*(seed: int) = last_total = walk(8, seed)
"""
    var current: ScriptCtx
    interp.implement_routine "enu_script_ctx_test", "host", "park",
      proc(a: VmArgs) {.gcsafe.} =
        {.gcsafe.}:
          current.pause()
          current.after_host_call()

    var ctxs: seq[ScriptCtx]
    for i in 0 ..< 4:
      let ctx = ScriptCtx(interpreter: interp)
      current = ctx
      ctx.load(script_dir / ("walker_" & $i & ".nim"), script)
      check not ctx.run(0)
      check ctx.call_proc("total", new_int_node(nkIntLit, i * 100)).paused
      ctxs.add ctx

    var live = ctxs.len
    var turn = 0
    while live > 0:
      # resume out of order: 0, 2, 1, 3, ...
      let i = [0, 2, 1, 3][turn mod 4]
      inc turn
      let ctx = ctxs[i]
      if ctx.tasks.len > 0:
        current = ctx
        if not ctx.resume():
          dec live
    # "s8" .. "s1" add 2 each on top of the seed
    for i, ctx in ctxs:
      check ctx.tasks.len == 0
      check ctx.get_var("last_total", "walker_" & $i).int_val == 16 + i * 100

  test "a failed eval doesn't skip the next module's statements":
    # loadModule resets the compiler's error counter; the VM's copy has to
    # follow or it silently drops the next top-level statement it compiles.
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load(script_dir / "evals.nim", "let x* = 1\n")
    check not ctx.run(0)
    interp.register_error_hook proc(
        config, info, msg, severity: auto
    ) {.gcsafe.} =
      discard
    discard ctx.eval("undeclared_thing = 1")

    var other = ScriptCtx(interpreter: interp)
    other.load(script_dir / "other.nim", "var loaded* = 1\n")
    check not other.run(0)
    check other.get_var("loaded", "other").int_val == 1

  test "host calls outside the script's own tasks don't exit it":
    # State initializers call into the VM directly with the player active,
    # possibly while its script has exited.
    var ctx = ScriptCtx(interpreter: interp)
    ctx.load(script_dir / "exited.nim", "var calls* = 0\n")
    check not ctx.run(0)
    interp.implement_routine "enu_script_ctx_test", "host", "park",
      proc(a: VmArgs) {.gcsafe.} =
        {.gcsafe.}:
          ctx.after_host_call()
    ctx.load(
      script_dir / "exited.nim",
      "import host\nvar calls* = 0\nproc call_host*() =\n  park()\n  inc calls\n",
    )
    check not ctx.run(0)
    ctx.exit_code = some(0)
    let call_host = interp.select_routine("call_host", module_name = "exited")
    discard interp.call_routine(call_host, [])
    check ctx.get_var("calls", "exited").int_val == 1
