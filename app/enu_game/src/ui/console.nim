import gdext
import gdext/classes/[gdrichtextlabel]
import core, gdutils

type Console* {.gdsync.} = ptr object of RichTextLabel

method ready*(self: Console) {.gdsync.} =
  # GD4: Console implementation needs significant rework
  # This is a stub to get compilation working
  discard