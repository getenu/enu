import gdext
import gdext/classes/[gdmargincontainer]
import core, gdutils

type Editor* {.gdsync.} = ptr object of MarginContainer

method ready*(self: Editor) {.gdsync.} =
  # GD4: Editor implementation needs significant rework
  # This is a stub to get compilation working
  discard