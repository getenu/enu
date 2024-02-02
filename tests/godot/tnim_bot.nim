import godot
import godotapi/[objects]
import engine/[engine, contexts]
import core, world/bot_node, globals
import os
include helper
import compiler/[vm, vmdef, options, lineinfos, ast, astalgo, renderer]

config.script_dir &= "/instancing"
let b = gdnew[BotNode]()

let script = nim_filename().parent_dir & "/scripts/instancing/box.nim"
b.paused = false
b.load_script(script)
b.engine.expose "vec_proc",
  proc(a: VmArgs): bool =
    let v = a.get_vec3(0)

    dump v
    let n = vec3(10.0, 9.0, 8.0).to_node
    a.set_result(n)
    result = false
assert b.engine.run()

while b.running:
  b.advance(0.5)

echo "Script is ", b.script
