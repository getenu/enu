import std/[sugar, os, monotimes]
import controllers/script_controllers, core, models

import libs/[interpreters, eval]

var state = GameState.active

state.logger =
  proc(level, msg: string) =
    echo level, ": ", msg

state.config.script_dir =
  current_source_path().parent_dir / "scripts" / "instancing"
state.config.lib_dir = current_source_path().parent_dir / ".." / ".." / "vmlib"

let controller = ScriptController.init

proc create(id: string): Bot =
  result = Bot.init()
  result.id = id

let bot1 = create("bot_script_1")
state.units.add bot1
let bot2 = create("bot_script_2")
state.units.add bot2
let bot3 = create("bot_script_3")
state.units.add bot3
