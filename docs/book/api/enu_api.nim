## Enu API Reference
## Generates the API documentation page for the Enu scripting API
## (share/vmlib/enu).

import nimib, nimibook
import ../../enuib
import ../../api_docs

# Load JSON documentation files at compile time.
# Generated from share/vmlib/enu by the `docs` task (generate_api_json in
# tasks.nim).
const
  types_json = static_read("json/enu/types.json")
  vectors_json = static_read("json/enu/vectors.json")
  base_bridge_json = static_read("json/enu/base_bridge.json")
  core_json = static_read("json/enu/core.json")
  builds_json = static_read("json/enu/builds.json")
  bots_json = static_read("json/enu/bots.json")
  players_json = static_read("json/enu/players.json")
  signs_json = static_read("json/enu/signs.json")
  state_machine_json = static_read("json/enu/state_machine.json")
  worlds_json = static_read("json/enu/worlds.json")
  testing_json = static_read("json/enu/testing.json")

const modules: seq[ModuleConfig] = @[
  ("enu/types", types_json),
  ("enu/vectors", vectors_json),
  ("enu/base_bridge", base_bridge_json),
  ("enu/core", core_json),
  ("enu/builds", builds_json),
  ("enu/bots", bots_json),
  ("enu/players", players_json),
  ("enu/signs", signs_json),
  ("enu/state_machine", state_machine_json),
  ("enu/worlds", worlds_json),
  ("enu/testing", testing_json),
]

nb_init(theme = use_enu_api_docs)

let data = collect_symbols(modules, include_free_procs = true)
nb.context["api"] = data.to_api_json()

nb_save
