import std/[strutils, math]
import types, base_api, vm_bridge_utils

bridged_to_host:
  proc all_bots(): seq[Bot]
  proc play*(self: Bot, animation_name: string)

proc all*(_: type Bot): seq[Bot] =
  all_bots()

proc walk*(self: Bot) =
  self.speed = 1.0

proc run*(self: Bot) =
  self.speed = 5.0

proc go_home*(self: Bot) =
  if ?self.sign:
    self.sign.show = false
  self.scale = 1
  self.glow = 0
  self.turn self.start_position, 2
  self.forward self.position.distance_to(self.start_position), 2
