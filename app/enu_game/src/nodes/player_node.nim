import gdext
import gdext/classes/[gdcharacterbody3d]
import core, gdutils, models

type PlayerNode* {.gdsync.} = ptr object of CharacterBody3D
  model*: Player
  velocity*: Vector3
  flying*: bool
  input_relative*: Vector2

method ready*(self: PlayerNode) {.gdsync.} =
  # GD4: Player implementation needs significant rework
  # This is a stub to get compilation working
  discard

proc update_raycast*(self: PlayerNode) =
  # GD4: Raycast system needs update
  discard

proc is_on_floor*(self: PlayerNode): bool =
  # GD4: Floor detection for CharacterBody3D
  result = self.is_on_floor()