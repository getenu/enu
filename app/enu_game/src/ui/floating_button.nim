import gdext
import gdext/classes/[gdbutton]
import core, gdutils

type FloatingButton* {.gdsync.} = ptr object of Button

method ready*(self: FloatingButton) {.gdsync.} =
  # GD4: FloatingButton implementation needs rework
  # This is a stub to get compilation working
  discard