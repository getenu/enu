import gdext
import gdext/classes/[gdsprite3d]
import core, gdutils, models

type AimTarget* {.gdsync.} = ptr object of Sprite3D

method ready*(self: AimTarget) {.gdsync.} =
  # GD4: AimTarget implementation needs significant rework
  # This is a stub to get compilation working
  discard