import engine/engine
import core
import std/os
import engine/contexts
let
  vmlib = "vmlib"
  e1 = Engine()
  e2 = Engine()
  script_dir = nim_filename().parent_dir & "/scripts"

e1.load("scripts", "test1", read_file script_dir & "/test1.nim", vmlib)
e2.load("scripts", "test2", read_file script_dir & "/test2.nim", vmlib)

e1.expose "callback",
  proc(a: VmArgs): bool =
    assert a.get_string(0) == "test1"
    result = true

e2.expose "callback",
  proc(a: VmArgs): bool =
    assert a.get_string(0) == "test2"
    result = true

for _ in 0 .. 1:
  assert e1.run()
  assert e2.run()

  for _ in 0 .. 9:
    assert e1.resume()
    assert e2.resume()

  assert not e1.resume()
  assert not e2.resume()

  echo "!!!!!!! RESTART !!!!!!!!!!"
