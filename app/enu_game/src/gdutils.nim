import std/[strformat]
import gdext
import core, models/[states]
export strformat.`&`, states, types

# Minimal gdutils implementation to get compilation working
# Many features are stubbed out pending further Godot 4 API research

proc bind_signal*(
    receiver: Object,
    sender: Object,
    signal: tuple[name: string, meth: string],
    binds: varargs[Variant] = @[],
) =
  # GD4: Signal binding needs significant rework
  discard

proc bind_signal*(
    receiver: Object,
    sender: Object,
    signal: string,
    binds: varargs[Variant] = @[],
) =
  bind_signal(receiver, sender, (signal, signal), binds)

proc bind_signals*(receiver, sender: Object, signals: varargs[string]) =
  # GD4: Multiple signal binding needs rework
  discard

proc bind_signals*(receiver: Node, signals: varargs[string]) =
  bind_signals(receiver, nil, signals)

proc trigger*(
    node: Object, signal: string, args: varargs[Variant]
) =
  # GD4: Signal triggering needs rework
  discard

proc `opacity=`*(node: Object, value: float) =
  # GD4: Modulate setting needs proper typing
  discard

proc opacity*(node: Object): float =
  # GD4: Modulate getting needs proper typing
  result = 1.0

proc trigger*(signal: string, args: varargs[Variant]) =
  trigger(state.nodes.game, signal, args)

template find*(self: Node, name: string, T: type Node): untyped =
  {.line.}:
    let obj = self.find_child(name) as T
    assert obj != nil
    obj

template find*(name: string, T: type Node): untyped =
  self.find(name, T)

const solid_alpha* = Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
const dimmed_alpha* = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.4)

proc ghost*(self: Object) =
  # GD4: Ghost functionality needs rework
  discard

proc unghost*(self: Object) =
  # GD4: Unghost functionality needs rework
  discard