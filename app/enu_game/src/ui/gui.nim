import gdext
import gdext/classes/[gdcontrol]
import core, gdutils

type GUI* {.gdsync.} = ptr object of Control

method ready*(self: GUI) {.gdsync.} =
  # GD4: GUI implementation needs significant rework
  # This is a stub to get compilation working
  discard