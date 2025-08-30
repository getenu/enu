import gdext
import gdext/classes/[gdnode3d, gdpackedscene, gdresourceloader]
import core, gdutils

type SignNode* {.gdsync.} =
  ptr object of Node3D
    model*: Sign

method ready*(self: SignNode) {.gdsync.} =
  # GD4: SignNode implementation needs significant rework
  # This is a stub to get compilation working
  discard

proc init*(_: type SignNode): SignNode =
  let scene =
    cast[gdref PackedScene](ResourceLoader.load("res://components/SignNode.tscn"))
  result = SignNode(scene[].instantiate)
