import engine/engine, core
import std/[strformat, sugar, os]

let
  vmlib = "vmlib"
  e1 = Engine()
  script_dir = nim_filename().parent_dir & "/scripts"
var
  counter = 0
  output = ""

e1.load("scripts", "bot", read_file script_dir & "/bots.nim", vmlib)
e1.expose("yield_script", a => true)

e1.expose "script_echo",
  proc(a: VmArgs): bool =
    let str = a.get_string(0)
    output &= str
    echo str

assert e1.run()
while e1.resume():
  discard e1.call_proc("set_action_running", e1.module_name, false)

let run_1 = output
output = ""
echo "---------"
assert e1.run()
while e1.resume():
  inc counter
  if counter == 4:
    discard e1.call_proc("set_action_running", e1.module_name, false)
    counter = 0

#assert run_1 == output
