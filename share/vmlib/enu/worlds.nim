import system except echo
import types, vm_bridge_utils

var world* = World()

bridged_to_host:
  proc environment*(self: World): string
    ## The world's scenery and lighting, like `"default"` or `"space"`.
    ## `world.environment = "space"`, instant outer space.

  proc `environment=`*(self: World, value: string)
  proc megapixels*(self: World): float
    ## How sharp the screen looks. Lower numbers are blurrier but
    ## faster, try turning this down if things get choppy.

  proc `megapixels=`*(self: World, value: float)
