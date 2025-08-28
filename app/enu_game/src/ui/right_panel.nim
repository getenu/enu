import gdext
import gdext/classes/[gdmargincontainer]
import core, gdutils

type RightPanel* {.gdsync.} = ptr object of MarginContainer

method ready*(self: RightPanel) {.gdsync.} =
  # GD4: RightPanel implementation needs significant rework
  # This is a stub to get compilation working
  discard