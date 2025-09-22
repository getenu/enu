import std/[strformat]
import gdext
import
  gdext/classes/[
    gdnode, gdcontrol, gdcanvasitem, gdoptionbutton, gdinputevent,
    gdinputeventscreentouch, gdscenetree,
  ]
import core, models/[states]
export strformat.`&`, states, types

Zen.thread_ctx = ZenContext.init(
  id = "main-{generate_id()}",
  chan_size = 2000,
  buffer = true,
  label = "main",
  max_recv_duration = (1.0 / 30.0).seconds,
)

state = GameState.init

proc trigger*(node: Object, signal: string, args: varargs[Variant]) =
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
    let obj = self.find_child(name) as T
    assert ?obj
    obj

template find*(name: string, T: type Node): untyped =
  self.find(name, T)

proc set_mouse_filter_recursive*(control: Control, mouse_filter: int) =
  control.mouse_filter = mouse_filter.Control_MouseFilter
  for child in control.get_children():
    let child_control = child as Control
    if ?child_control:
      child_control.set_mouse_filter_recursive(mouse_filter)

const solid_alpha* = color(1.0, 1.0, 1.0, 1.0)
const dimmed_alpha* = color(1.0, 1.0, 1.0, 0.4)

proc ghost*(self: Control) =
  # Modulation disabled - no visual changes for command mode
  # # GD4: Mouse filter constants need to be investigated
  # # self.set_mouse_filter_recursive(Control.MOUSE_FILTER_IGNORE.int)
  # self.modulate = dimmed_alpha
  discard

proc unghost*(self: Control) =
  # Modulation disabled - no visual changes
  # # GD4: Mouse filter constants need to be investigated
  # # self.set_mouse_filter_recursive(Control.MOUSE_FILTER_PASS.int)
  # # self.mouse_filter = Control.MOUSE_FILTER_STOP
  # self.modulate = solid_alpha
  discard

proc select*(self: OptionButton, text: string): int {.discardable.} =
  for i in 0 ..< self.get_item_count():
    if $self.get_item_text(i) == text:
      self.select(i)
      return i
  result = -1

proc ignore_touches*(self: Control, event: InputEvent) =
  if event.is_class("InputEventScreenTouch") and
      TouchControls in state.local_flags:
    let touch_event = event as InputEventScreenTouch
    if touch_event.pressed and touch_event.position.x >= self.global_position.x and
        touch_event.position.x <= self.global_position.x + self.size.x and
        touch_event.position.y >= self.global_position.y and
        touch_event.position.y <= self.global_position.y + self.size.y:
      state.ignored_touches.incl byte(touch_event.index)
      # GD4: set_input_as_handled method API needs investigation
      # self.get_tree().set_input_as_handled()

proc standalone*(node: Node): bool =
  node.get_parent() == node.get_tree().root
