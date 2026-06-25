import types, base_api, vm_bridge_utils, builds_private

bridged_to_host:
  proc tool*(self: Player): Tools
  proc `tool=`*(self: Player, value: Tools)
  proc tools_has*(self: Player, tool: Tools): bool
  proc tools_incl*(self: Player, tool: Tools)
  proc tools_excl*(self: Player, tool: Tools)
  proc tools_clear*(self: Player)
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

type ToolSet* = distinct Player
  ## Set-like view over a player's available tools. Operations forward to the
  ## host one tool at a time, so no real set crosses the bridge.

proc tools*(self: Player): ToolSet =
  ToolSet(self)

proc contains*(tools: ToolSet, tool: Tools): bool =
  Player(tools).tools_has(tool)

proc incl*(tools: ToolSet, tool: Tools) =
  Player(tools).tools_incl(tool)

proc excl*(tools: ToolSet, tool: Tools) =
  Player(tools).tools_excl(tool)

proc clear*(tools: ToolSet) =
  Player(tools).tools_clear()

iterator items*(tools: ToolSet): Tools =
  for tool in CodeMode .. PlaceBot:
    if tool in tools:
      yield tool

proc len*(tools: ToolSet): int =
  for _ in tools:
    inc result

proc `$`*(tools: ToolSet): string =
  result = "{"
  for tool in tools:
    if result.len > 1:
      result &= ", "
    result &= $tool
  result &= "}"

proc `tools=`*(self: Player, value: set[Tools]) =
  ## Replace the available tools with `value` (a normal VM set literal, iterated
  ## here — never marshalled). `None` is ignored; it isn't a selectable tool.
  self.tools_clear()
  for tool in value:
    if tool != None:
      self.tools_incl(tool)
