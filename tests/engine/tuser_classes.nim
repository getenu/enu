import engine/engine
import core
import std/[os, strutils]

var output = ""
let
  vmlib = "vmlib"
  e = Engine()
  script_dir = nim_filename().parent_dir & "/scripts"
  prefix = "proc log*(s:string) = discard\n"
  user_classes1 =
    """
    type
      Type1* = object
        name*: string
  """.dedent
  user_classes2 =
    """
    type
      Type1* = object
        name*: string
        size*: int
      Type2* = object
        name*: string
  """.dedent
  script1 =
    prefix &
    """
    import user_classes
    let a = Type1(name: "type1")
    log "a=" & a.repr
  """.dedent
  script2 =
    prefix &
    """
    import user_classes
    let a = Type1(name: "type1", size: 5)
    let b = Type2(name: "type2")
    log "a=" & a.repr
    log "b=" & b.repr
  """.dedent

e.load(script_dir, script_dir & "/user_classes.nim", user_classes1, vmlib)
assert not e.run()

e.load(script_dir, "script", script1, vmlib)
e.expose "log",
  proc(a: VmArgs): bool =
    let msg = a.get_string(0)
    echo msg
    output &= msg & "\n"
assert not e.run()

e.load(script_dir, script_dir & "/user_classes.nim", user_classes2, vmlib)
assert not e.run()

e.load(script_dir, "script", script2, vmlib)
assert not e.run()

assert output ==
  """
  a=(name: "type1")
  a=(name: "type1", size: 5)
  b=(name: "type2")
""".dedent
