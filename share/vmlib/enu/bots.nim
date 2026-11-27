import std/[strutils, math]
import core, vm_bridge_utils, signs

bridged_to_host:
  proc play*(self: Bot, animation_name: string)
    ## Play an animation by name, like `play "wave"`. Play `""` to
    ## stop.


proc go_home*(self: Bot) =
  ## Head back to the start position by turning around and walking
  ## there. Also resets scale, glow, and hides any open sign.
  self.say()
  self.scale = 1
  self.glow = 0
  self.turn self.start_position, 2
  self.forward self.position.distance_to(self.start_position), 2
