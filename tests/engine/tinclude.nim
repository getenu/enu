import engine/engine
import core
import std/[os, strutils]

var output = ""
let
  vmlib = "vmlib"
  e = Engine()
  script_dir = nim_filename().parent_dir & "/scripts/instancing"
  script_1 =
    """
    var place = "script 1 header"
    proc in_script_1_header*() = echo "in script 1 header"
    include "script_1.nim"
  """.dedent
  script_2 =
    """
    import script_1
    var place = "script 2 header"
    proc in_script_2_header*() = echo "in script 2 header"
    include "script_2.nim"
    in_script_1_header()
    in_script_1_body()
    in_script_2_header()
    in_script_2_body()
  """.dedent

e.load(script_dir, script_dir & "/script_1.nim", script_1, vmlib)
assert not e.run()

e.load(script_dir, script_dir & "/script_2.nim", script_2, vmlib)
assert not e.run()

# e.load(script_dir, "script", script1, vmlib)
# e.expose "log", proc(a: VmArgs): bool =
#   let msg = a.get_string(0)
#   echo msg
#   output &= msg & "\n"
# assert not e.run()
#
# e.load(script_dir, script_dir & "/user_classes.nim", user_classes2, vmlib)
# assert not e.run()
#
# e.load(script_dir, "script", script2, vmlib)
# assert not e.run()

# assert output == """
#   a=(name: "type1")
#   a=(name: "type1", size: 5)
#   b=(name: "type2")
# """.dedent
