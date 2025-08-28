import gdext
import gdext/classes/[gdnode3d]
import core, gdutils

type SignNode* {.gdsync.} = ptr object of Node3D
  model*: Sign

method ready*(self: SignNode) {.gdsync.} =
  # GD4: SignNode implementation needs significant rework
  # This is a stub to get compilation working
  discard