import gdext
import gdext/classes/gdNode

import std/strutils

type MyClass* {.gdsync.} = ptr object of Node
  # {.gdexport.} to publish the property to editor. Do not forget to export it with `*`.
  message* {.gdexport.}: string = "This is MyClass."
  address: uint64

# {.name.} enables to override the function name visible from the editor.
proc address_readable(self: MyClass): string {.gdsync, name: "get_address_readable".} =
  self.address.toHex.insertSep(' ', 4)

# If you need to customize the getter/setter of property, same-name macros of the pragma is available.
# gdsync'ed procs or lambdas are allowed for getter/setter.
gdexport "address_readable",
  address_readable,
  proc (self: MyClass; value: string) = (discard)

# {.gdsync, signal.} enables to define signal. Note that the return type must be Error.
proc mySignal(self: MyClass): Error {.gdsync, signal.}

proc myCallable(self: MyClass) {.gdsync.} =
  printRich self.message, " It's allocated at [b]", self.address_readable, "[/b]."

# onInit is like a constructor. That is called at the class is created.
# This is not a part of GDExtension so, gdsync is not required.
method onInit(self: MyClass) =
  self.address = cast[uint64](self)

method ready(self: MyClass) {.gdsync.} =
  assert self.connect("mySignal", self.callable "myCallable") == ok
  assert self.mySignal() == ok

method process(self: MyClass; delta: float) {.gdsync.} =
  discard