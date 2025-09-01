import std/[strformat]
import gdext
import gdext/classes/[gdnode, gdcontrol, gdcanvasitem, gdoptionbutton, gdinputevent, gdinputeventscreentouch]
import core, models/[states]
export strformat.`&`, states, types

proc bind_signal*(
    receiver: Object,
    sender: Object,
    signal: tuple[name: string, meth: string],
    binds: varargs[Variant] = @[],
) =
  # Create user signal if it doesn't exist
  if not sender.has_signal(signal.name):
    sender.add_user_signal(signal.name)
  
  # Convert method name to proper format
  var method_name = signal.meth
  if not signal.meth.starts_with("_"):
    method_name = "_on_" & method_name
  
  # Create Callable and connect signal
  let callable_obj = callable(receiver, newStringName(method_name))
  discard sender.connect(newStringName(signal.name), callable_obj)

proc bind_signal*(
    receiver: Object,
    sender: Object,
    signal: string,
    binds: varargs[Variant] = @[],
) =
  bind_signal(receiver, sender, (signal, signal), binds)

proc bind_signals*(receiver, sender: Object, signals: varargs[string]) =
  let send_node = if sender == nil: state.nodes.game else: sender

  for signal in signals:
    receiver.bind_signal(send_node, signal)

proc bind_signals*(receiver: Node, signals: varargs[string]) =
  bind_signals(receiver, nil, signals)

proc trigger*(
    node: Object, signal: string, args: varargs[Variant]
) =
  if not node.has_user_signal(signal):
    node.add_user_signal(signal)
  # Emit signal with arguments
  discard node.emit_signal(newStringName(signal), args)

proc `opacity=`*(node: CanvasItem, value: float) =
  node.modulate = color(1.0, 1.0, 1.0, value)

proc opacity*(node: CanvasItem): float =
  node.modulate.a

proc trigger*(signal: string, args: varargs[Variant]) =
  trigger(state.nodes.game, signal, args)

template find*(self: Node, name: string, T: type Node): untyped =
  {.line.}:
    let obj = self.find_child(name, false, false) as T
    if obj.is_nil():
      print("[GDUTILS] Warning: Could not find node '", name, "' of type ", $T)
    obj

template find*(name: string, T: type Node): untyped =
  self.find(name, T)

proc set_mouse_filter_recursive*(control: Control, mouse_filter: int) =
  control.mouse_filter = mouse_filter.Control_MouseFilter
  for child in control.get_children():
    let child_control = child as Control
    if not child_control.is_nil():
      child_control.set_mouse_filter_recursive(mouse_filter)

const solid_alpha* = color(1.0, 1.0, 1.0, 1.0)
const dimmed_alpha* = color(1.0, 1.0, 1.0, 0.4)

proc ghost*(self: Control) =
  # GD4: Mouse filter constants need to be investigated 
  # self.set_mouse_filter_recursive(Control.MOUSE_FILTER_IGNORE.int)
  self.modulate = dimmed_alpha

proc unghost*(self: Control) =
  # GD4: Mouse filter constants need to be investigated
  # self.set_mouse_filter_recursive(Control.MOUSE_FILTER_PASS.int)
  # self.mouse_filter = Control.MOUSE_FILTER_STOP
  self.modulate = solid_alpha

proc select*(self: OptionButton, text: string): int {.discardable.} =
  for i in 0 ..< self.get_item_count():
    if $self.get_item_text(i) == text:
      self.select(i)
      return i
  result = -1

proc ignore_touches*(self: Control, event: InputEvent) =
  if event.is_class("InputEventScreenTouch") and TouchControls in state.local_flags:
    let touch_event = event as InputEventScreenTouch
    if touch_event.pressed and
        touch_event.position.x >= self.global_position.x and
        touch_event.position.x <= self.global_position.x + self.size.x and
        touch_event.position.y >= self.global_position.y and
        touch_event.position.y <= self.global_position.y + self.size.y:
      state.ignored_touches.incl byte(touch_event.index)
      # GD4: set_input_as_handled method API needs investigation
      # self.get_tree().set_input_as_handled()