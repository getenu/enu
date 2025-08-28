import gdext
import gdext/classes/[gdscrollcontainer]
import core, gdutils

type MarkdownLabel* {.gdsync.} = ptr object of ScrollContainer

method ready*(self: MarkdownLabel) {.gdsync.} =
  # GD4: MarkdownLabel implementation needs significant rework
  # This is a stub to get compilation working
  discard