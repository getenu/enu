import std/[strformat]
import pkg/[godot]
import godotapi/[node, scene_tree, voxel_buffer]
import core, models/[states]
export strformat.`&`, states, types

proc bind_signals*(receiver, sender: Object, signals: varargs[string]) =
  let send_node = if sender == nil: state.nodes.game else: sender

  for signal in signals:
    let meth = "_on_" & signal
    if not send_node.has_signal(signal):
      send_node.add_user_signal(signal)
    discard send_node.connect(signal, receiver, meth)

proc bind_signals*(receiver: Node, signals: varargs[string]) =
  bind_signals(receiver, nil, signals)

proc trigger*(
    node: Object, signal: string, args: varargs[Variant, `new_variant`]
) =
  if not node.has_user_signal(signal):
    node.add_user_signal(signal)
  node.emit_signal(signal, args)

proc trigger*(signal: string, args: varargs[Variant]) =
  trigger(state.nodes.game, signal, args)
