import gdext
import gdext/classes/[gdcharacterbody3d, gdpackedscene, gdresourceloader]
import core, gdutils, models

type BotNode* {.gdsync.} = ptr object of CharacterBody3D
  model*: Unit

method ready*(self: BotNode) {.gdsync.} =
  # GD4: Bot node implementation needs rework
  # This is a stub to get compilation working
  discard

proc init*(_: type BotNode): BotNode =
  let scene = cast[gdref PackedScene](ResourceLoader.load("res://components/Bot.tscn"))
  result = BotNode(scene[].instantiate)