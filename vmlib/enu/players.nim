import types, base_api, vm_bridge_utils

bridged_to_host:
  proc tool*(self: Player): Tools
  proc `tool=`*(self: Player, value: Tools)
  proc playing*(self: Player): bool
  proc `playing=`*(self: Player, value: bool)
  proc flying*(self: Player): bool
  proc `flying=`*(self: Player, value: bool)
  proc running*(self: Player): bool
  proc `running=`*(self: Player, value: bool)
  proc god*(self: Player): bool
  proc `god=`*(self: Player, value: bool)
  proc coding*(self: Player): Unit
  proc `coding=`*(self: Player, value: Unit)
  proc open_sign*(self: Player): Sign
  proc `open_sign=`*(self: Player, value: Sign)
  proc executing_player*(): Player
  proc block_log*(self: Unit): string
  proc clear_block_log*(self: Unit)

var player*: Player
template runner*(): Player =
  executing_player()

register_state_init(
  proc() =
    player = Player.first
)

proc number*(self: Player): int =
  for i, player in all_players():
    if player == self:
      return i + 1

  raise newException(ValueError, "Player not found in player list")
