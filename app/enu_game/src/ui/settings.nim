import gdext
import gdext/classes/[gdpanelcontainer]
import core, gdutils

type Settings* {.gdsync.} = ptr object of PanelContainer

method ready*(self: Settings) {.gdsync.} =
  # GD4: Settings implementation needs significant rework
  # This is a stub to get compilation working
  discard