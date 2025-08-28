import gdext/classes/[gdmeshinstance3d]
import gdext
import core, gdutils, models

type GroundNode* {.gdsync.} = ptr object of MeshInstance3D
  model*: Ground

method ready*(self: GroundNode) {.gdsync.} =
  self.model = Ground.init(self)
  state.ground = self.model