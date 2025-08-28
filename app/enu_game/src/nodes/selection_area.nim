import gdext
import gdext/classes/[gdarea3d]
import core, gdutils

type SelectionArea* {.gdsync.} = ptr object of Area3D

method ready*(self: SelectionArea) {.gdsync.} =
  # GD4: SelectionArea implementation needs rework
  # This is a stub to get compilation working
  discard