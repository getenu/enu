import std/[strutils, math]
import core, vm_bridge_utils

bridged_to_host:
  proc play*(self: Bot, animation_name: string)
    ## Play an animation by name, like `play "wave"`. Play `""` to
    ## stop.

proc walk*(self: Bot) =
  ## Walking speed. The same as `speed = 1`.
  self.speed = 1.0

proc run*(self: Bot) =
  ## Running speed. The same as `speed = 5`.
  self.speed = 5.0

proc go_home*(self: Bot) =
  ## Head back to the start position by turning around and walking
  ## there. Also resets scale, glow, and hides any open sign.
  if ?self.sign:
    self.sign.show = false
  self.scale = 1
  self.glow = 0
  self.turn self.start_position, 2
  self.forward self.position.distance_to(self.start_position), 2
