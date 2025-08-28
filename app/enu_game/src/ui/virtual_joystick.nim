import gdext
import gdext/classes/[gdcontrol]
import core, gdutils

type VirtualJoystick* {.gdsync.} = ptr object of Control

method ready*(self: VirtualJoystick) {.gdsync.} =
  # GD4: VirtualJoystick implementation needs significant rework
  # This is a stub to get compilation working
  discard