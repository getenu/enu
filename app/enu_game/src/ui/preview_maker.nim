import gdext
import gdext/classes/[gdviewport]
import core, gdutils

type PreviewMaker* {.gdsync.} = ptr object of Viewport

method ready*(self: PreviewMaker) {.gdsync.} =
  # GD4: PreviewMaker implementation needs significant rework
  # This is a stub to get compilation working
  discard