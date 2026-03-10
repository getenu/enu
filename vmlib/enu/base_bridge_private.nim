import types, vm_bridge_utils

proc read_enu_script*(filename: string): string {.compileTime.} =
  # In nimsuggest mode, staticRead registers the script as a dependency and
  # confuses nimsuggest about the module's source file, returning ??? for
  # module navigation. gorge reads without that side effect; parse_stmt in
  # the macro still uses the script path so line info and symbol navigation
  # point to the real script file.
  when defined(nimsuggest):
    gorge("cat " & filename)
  else:
    staticRead(filename)

bridged_to_host:
  proc action_running*(self: Unit): bool
  proc `action_running=`*(self: Unit, value: bool)
  proc yield_script*(self: Unit)
  proc begin_move*(self: Unit, direction: Vector3, steps: float, move_mode: int)

  proc begin_turn*(
    self: Unit, axis: Vector3, steps: float, lean: bool, move_mode: int
  )

  proc sleep_impl*(seconds = 1.0)
  proc position_set*(self: Unit, position: Vector3)

  proc new_markdown_sign*(
    self: Unit,
    instance: Sign,
    message: string,
    more = "",
    width = 1.0,
    height = 1.0,
    size = 32,
    billboard = false,
  )

  proc update_markdown_sign*(
    self: Sign,
    message: string,
    more = "",
    width = 1.0,
    height = 1.0,
    size = 32,
    billboard = false,
  )
