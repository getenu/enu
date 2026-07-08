## Signs and speech: `say` something, and control how the sign looks.

import system except echo
import std/[strutils, math, wrapnils, options]
import core, vm_bridge_utils, base_bridge_private

bridged_to_host:
  proc message*(self: Sign): string
    ## The text on the sign. It's markdown, so `**bold**`, lists and
    ## headings all work.

  proc `message=`*(self: Sign, value: string)
  proc more*(self: Sign): string
    ## Extra text shown when the player opens the sign — good for
    ## the long version of the story.

  proc `more=`*(self: Sign, value: string)
  proc width*(self: Sign): float
    ## How wide the sign is, in blocks.

  proc `width=`*(self: Sign, value: float)
  proc height*(self: Sign): float
    ## How tall the sign is, in blocks.

  proc `height=`*(self: Sign, value: float)
  proc size*(self: Sign): int
    ## The text size. Bigger numbers, bigger letters.

  proc `size=`*(self: Sign, value: int)
  proc open*(self: Sign): bool
    ## Whether the sign is open full-screen for reading. Set it to pop
    ## the sign open (or slam it shut).

  proc `open=`*(self: Sign, value: bool)
  proc billboard*(self: Sign): bool
    ## Whether the sign spins to always face the player, like it's
    ## watching you. (Politely.)

  proc `billboard=`*(self: Sign, value: bool)

proc say*(
    self: Thing,
    message: string,
    more = "",
    width = float.high,
    height = float.high,
    size = int.high,
    billboard = none(bool),
): Sign {.discardable.} =
  ## Show a message on a sign above the thing: `say "Hello!"`. Call it
  ## again to change the message, or `say ""` to put the sign away.
  ## Markdown works, `more` adds extra text for when the sign is
  ## opened, and `width`/`height`/`size` control the shape if you're
  ## picky.
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
