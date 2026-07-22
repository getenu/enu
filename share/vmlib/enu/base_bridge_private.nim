import types, vm_bridge_utils

proc read_enu_script*(filename: string): string {.compileTime.} =
  static_read(filename)

bridged_to_host:
  proc action_running*(self: Thing): bool
  proc `action_running=`*(self: Thing, value: bool)
  proc yield_script*(self: Thing)
  proc begin_move*(self: Thing, direction: Vector3, steps: float, move_mode: int)

  proc begin_turn*(
    self: Thing, axis: Vector3, steps: float, lean: bool, move_mode: int
  )

  proc sleep_impl*(seconds = 1.0)
  proc position_set*(self: Thing, position: Vector3)
  proc start_position_set*(self: Thing, position: Vector3)
  proc reset_anchor*(self: Thing)
  proc delete*(self: Thing)
  proc keep_alive*()
  proc claim_name*(requested: string)

  proc new_markdown_sign*(
    self: Thing,
    instance: Sign,
    message: string,
    more = "",
    width = 1.0,
    height = 1.0,
    size = 250 / 1200, # text height in blocks; ≈0.208 == the pre-blocks default
    billboard = false,
  )

  proc update_markdown_sign*(
    self: Sign,
    message: string,
    more = "",
    width = 1.0,
    height = 1.0,
    size = 250 / 1200, # text height in blocks; ≈0.208 == the pre-blocks default
    billboard = false,
  )
