import gdext
import gdext/classes/[gdcharacterbody3d]
import core, gdutils, models

type BotNode* {.gdsync.} = ptr object of CharacterBody3D
  model*: Unit

method ready*(self: BotNode) {.gdsync.} =
  # GD4: Bot node implementation needs rework
  # This is a stub to get compilation working
  discard