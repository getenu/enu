import system except echo
import types, vm_bridge_utils

var world* = World()

bridged_to_host:
  proc environment*(self: World): string
  proc `environment=`*(self: World, value: string)
  proc megapixels*(self: World): float
  proc `megapixels=`*(self: World, value: float)
