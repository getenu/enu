## Commands for the people playing: their tools, whether they're flying
## or playing, and what they have open.

import core, vm_bridge_utils, builds_private

bridged_to_host:
  proc tool*(self: Player): Tools
    ## The tool the player is holding right now, like `CodeMode` or
    ## `BlueBlock`. Assign to switch tools for them.

  proc `tool=`*(self: Player, value: Tools)
  proc tools_has*(self: Player, tool: Tools): bool
  proc tools_incl*(self: Player, tool: Tools)
  proc tools_excl*(self: Player, tool: Tools)
  proc tools_clear*(self: Player)
  proc playing*(self: Player): bool
    ## `true` in play mode, `false` in edit mode. Assign to switch.

  proc `playing=`*(self: Player, value: bool)
  proc flying*(self: Player): bool
    ## Whether the player is flying. `player.flying = true`, no
    ## double-jump needed.

  proc `flying=`*(self: Player, value: bool)
  proc running*(self: Player): bool
    ## Whether the player is running.

  proc `running=`*(self: Player, value: bool)
  proc god*(self: Player): bool
    ## God mode: hidden things show up, and locked things can be
    ## edited. With great power, etc.

  proc `god=`*(self: Player, value: bool)
  proc coding*(self: Player): Thing
    ## The thing whose code the player has open, or `nil` if the editor
    ## is closed. Assign a thing to open its code for them.

  proc `coding=`*(self: Player, value: Thing)
  proc open_sign*(self: Player): Sign
    ## The sign the player is reading, or `nil` if none. Assign a sign
    ## to shove it in front of them.

  proc `open_sign=`*(self: Player, value: Sign)
  proc executing_player*(): Player
    ## The player who ran this script. `runner` is the friendly name.

  proc block_log*(self: Thing): string
  proc clear_block_log*(self: Thing)

var player*: Player
template runner*(): Player =
  ## The player who ran this script, useful in multiplayer, where
  ## `player` is just the first one.
  executing_player()

register_state_init(
  proc() =
    player = Player.first
)

proc number*(self: Player): int =
  ## Which player this is: player 1, player 2, and so on.
  for i, player in all_players():
    if player == self:
      return i + 1

  raise newException(ValueError, "Player not found in player list")

type ToolSet* = distinct Player
  ## Set-like view over a player's available tools. Operations forward to the
  ## host one tool at a time, so no real set crosses the bridge.

proc tools*(self: Player): ToolSet =
  ## The tools in the player's toolbar. Check with `in`, add with
  ## `incl`, remove with `excl`, or assign a whole set:
  ## `player.tools = {CodeMode, BlueBlock}`.
  ToolSet(self)

proc contains*(tools: ToolSet, tool: Tools): bool =
  ## `true` if the tool is in the toolbar:
  ## `if PlaceBot in player.tools:`.
  Player(tools).tools_has(tool)

proc incl*(tools: ToolSet, tool: Tools) =
  ## Add a tool to the toolbar.
  Player(tools).tools_incl(tool)

proc excl*(tools: ToolSet, tool: Tools) =
  ## Take a tool out of the toolbar.
  Player(tools).tools_excl(tool)

proc clear*(tools: ToolSet) =
  ## Empty the toolbar completely.
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
  ## Replace the whole toolbar at once:
  ## `player.tools = {CodeMode, BlueBlock, PlaceBot}`.
  self.tools_clear()
  for tool in value:
    if tool != None:
      self.tools_incl(tool)
