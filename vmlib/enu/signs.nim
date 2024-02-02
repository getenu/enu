import system except echo
import std/[strutils, math, wrapnils, options]
import types, base_api, vm_bridge_utils, base_bridge_private

bridged_to_host:
  proc message*(self: Sign): string =
    discard

  proc `message=`*(self: Sign, value: string) =
    discard

  proc more*(self: Sign): string =
    discard

  proc `more=`*(self: Sign, value: string) =
    discard

  proc width*(self: Sign): float =
    discard

  proc `width=`*(self: Sign, value: float) =
    discard

  proc height*(self: Sign): float =
    discard

  proc `height=`*(self: Sign, value: float) =
    discard

  proc size*(self: Sign): int =
    discard

  proc `size=`*(self: Sign, value: int) =
    discard

  proc open*(self: Sign): bool =
    discard

  proc `open=`*(self: Sign, value: bool) =
    discard

  proc billboard*(self: Sign): bool =
    discard

  proc `billboard=`*(self: Sign, value: bool) =
    discard

proc say*(
    self: Unit,
    message: string,
    more = "",
    width = float.high,
    height = float.high,
    size = int.high,
    billboard = none(bool),
): Sign {.discardable.} =
  let defaults: tuple[width: float, height: float, size: int, billboard: bool] =
    if ?self.sign:
      (self.sign.width, self.sign.height, self.sign.size, self.sign.billboard)
    elif self of Bot:
      (2.0, 0.0, 250, true)
    else:
      (2.0, 2.0, 250, false)

  let
    width = if width == float.high: defaults.width else: width
    height = if height == float.high: defaults.height else: height
    size = if size == int.high: defaults.size else: size
    billboard = billboard.get(defaults.billboard)

  if message == "":
    if ?self.sign:
      self.sign.show = false
  elif self of Bot and ?self.sign:
    result = self.sign
    result.update_markdown_sign(message, more, width, height, size, billboard)
    result.show = true
  else:
    result = Sign()
    self.new_markdown_sign(
      result, message, more, width, height, size, billboard
    )

    self.sign = result

    if self of Build and height > 1.0:
      result.position = result.position + (UP * (height - 1.0))
    elif self of Bot:
      result.position = result.position + (UP * 2) + (LEFT * 1)

template say*(
    message: string,
    more = "",
    width = float.high,
    height = float.high,
    size = int.high,
    billboard = none(bool),
): Sign =
  enu_target.say(message, more, width, height, size, billboard)
