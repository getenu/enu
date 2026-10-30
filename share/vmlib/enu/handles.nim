## Things cross the host bridge as integer handles that the host assigns.
## This registry maps a handle back to the script-side object. Handle 0 is
## `nil`.

import std/importutils
import types

private_access Thing

var registry: seq[Thing]

proc thing_kind_impl(handle: int): string =
  raise_assert "thing_kind_impl must be implemented by host"

proc bridge_handle*(self: Thing): int =
  if self.is_nil: 0 else: self.bridge_handle

proc register_handle*(self: Thing, handle: int) =
  assert handle > 0
  self.bridge_handle = handle
  if registry.len <= handle:
    registry.set_len(handle + 1)
  registry[handle] = self

proc thing_for_handle*(handle: int): Thing =
  ## The object for `handle`. Things the host made without a script (the
  ## player, a sign another script dropped) get one on first use.
  if handle == 0:
    return nil
  if handle < registry.len and not registry[handle].is_nil:
    return registry[handle]
  result =
    case thing_kind_impl(handle)
    of "Bot": Bot()
    of "Build": Build()
    of "Sign": Sign()
    of "Player": Player()
    else: raise_assert "unknown thing kind for handle " & $handle
  result.register_handle(handle)
