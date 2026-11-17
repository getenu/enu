## A tiny UI layer with one API and two backends: native (Blitz through the
## enu_web C interface) and JS (the browser DOM, via `nim js`). App code is
## written once against this module. A VM backend would sit beside these,
## going through Enu's host bridge.

when defined(js):
  import std/dom

  type
    Elem* = object
      node: dom.Node

    Ui* = ref object

  proc new_ui*(html: string, width = 0, height = 0): Ui =
    document.body.innerHTML = cstring(html)
    Ui()

  proc query*(ui: Ui, selector: string): Elem =
    Elem(node: document.querySelector(cstring(selector)))

  proc element*(ui: Ui, tag: string): Elem =
    Elem(node: document.createElement(cstring(tag)))

  proc `[]=`*(ui: Ui, e: Elem, name, value: string) =
    dom.Element(e.node).setAttribute(cstring(name), cstring(value))

  proc set_text*(ui: Ui, e: Elem, value: string) =
    e.node.textContent = cstring(value)

  proc add*(ui: Ui, parent, child: Elem) =
    parent.node.appendChild(child.node)

  proc remove*(ui: Ui, e: Elem) =
    e.node.parentNode.removeChild(e.node)

  proc on_click*(ui: Ui, e: Elem, handler: proc()) =
    e.node.addEventListener("click", proc(ev: Event) = handler())

else:
  import std/tables
  import enu_web

  type
    Elem* = object
      id*: NodeId

    Ui* = ref object
      view*: ViewPtr
      width*, height*: int
      handlers: Table[uint64, proc()]

  proc new_ui*(html: string, width = 1200, height = 1200): Ui =
    Ui(
      view: ew_view_new(cstring(html), width.uint32, height.uint32, 1.0),
      width: width,
      height: height,
    )

  proc close*(ui: Ui) =
    ew_view_free(ui.view)

  proc query*(ui: Ui, selector: string): Elem =
    Elem(id: ew_query(ui.view, cstring(selector)))

  proc element*(ui: Ui, tag: string): Elem =
    Elem(id: ew_create_element(ui.view, cstring(tag)))

  proc `[]=`*(ui: Ui, e: Elem, name, value: string) =
    ew_set_attribute(ui.view, e.id, cstring(name), cstring(value))

  proc set_text*(ui: Ui, e: Elem, value: string) =
    ew_set_text(ui.view, e.id, cstring(value))

  proc add*(ui: Ui, parent, child: Elem) =
    ew_append(ui.view, parent.id, child.id)

  proc remove*(ui: Ui, e: Elem) =
    ui.handlers.del(uint64(e.id))
    ew_remove(ui.view, e.id)

  proc on_click*(ui: Ui, e: Elem, handler: proc()) =
    ui.handlers[uint64(e.id)] = handler

  proc click*(ui: Ui, x, y: float): bool =
    ## Dispatches a click at a point in pixels, bubbling to the nearest
    ## ancestor with a handler. Returns whether anything handled it.
    var n = ew_element_at(ui.view, x.float32, y.float32)
    while n != NO_NODE:
      if uint64(n) in ui.handlers:
        ui.handlers[uint64(n)]()
        return true
      n = ew_parent(ui.view, n)

  proc render*(ui: Ui): ptr UncheckedArray[uint8] =
    ew_render(ui.view)

  proc content_height*(ui: Ui): float =
    ew_content_height(ui.view)

  proc save_png*(ui: Ui, path: string) =
    discard ew_render(ui.view)
    doAssert ew_write_png(ui.view, cstring(path))

# --- canvas ------------------------------------------------------------------
#
# A subset of CanvasRenderingContext2D. Colors are 0xRRGGBBAA.

when defined(js):
  import std/jsffi

  type Canvas* = object
    ctx: JsObject

  proc css(color: uint32): cstring =
    cstring(
      "rgba(" & $(color shr 24) & "," & $((color shr 16) and 0xff) & "," &
        $((color shr 8) and 0xff) & "," & $(float(color and 0xff) / 255) & ")"
    )

  proc canvas*(ui: Ui, e: Elem): Canvas =
    Canvas(ctx: e.node.to_js.getContext("2d"))

  proc clear*(c: Canvas) =
    let el = c.ctx.canvas
    discard c.ctx.clearRect(0, 0, el.width, el.height)

  proc begin_path*(c: Canvas) = discard c.ctx.beginPath()
  proc move_to*(c: Canvas, x, y: float) = discard c.ctx.moveTo(x, y)
  proc line_to*(c: Canvas, x, y: float) = discard c.ctx.lineTo(x, y)
  proc quad_to*(c: Canvas, cx, cy, x, y: float) = discard c.ctx.quadraticCurveTo(cx, cy, x, y)
  proc cubic_to*(c: Canvas, c1x, c1y, c2x, c2y, x, y: float) =
    discard c.ctx.bezierCurveTo(c1x, c1y, c2x, c2y, x, y)
  proc close_path*(c: Canvas) = discard c.ctx.closePath()
  proc fill*(c: Canvas, color: uint32) =
    c.ctx.fillStyle = css(color)
    discard c.ctx.fill()
  proc stroke*(c: Canvas, color: uint32, width: float) =
    c.ctx.strokeStyle = css(color)
    c.ctx.lineWidth = width
    discard c.ctx.stroke()
  proc font(size: float, bold: bool): cstring =
    cstring((if bold: "bold " else: "") & $size & "px sans-serif")
  proc fill_text*(c: Canvas, text: string, x, y, size: float, color: uint32, bold = false) =
    c.ctx.font = font(size, bold)
    c.ctx.fillStyle = css(color)
    discard c.ctx.fillText(cstring(text), x, y)
  proc measure_text*(c: Canvas, text: string, size: float, bold = false): float =
    c.ctx.font = font(size, bold)
    c.ctx.measureText(cstring(text)).width.to(float)

else:
  type Canvas* = object
    view: ViewPtr
    node: NodeId

  proc canvas*(ui: Ui, e: Elem): Canvas =
    ew_canvas_attach(ui.view, e.id)
    Canvas(view: ui.view, node: e.id)

  proc clear*(c: Canvas) = ew_canvas_clear(c.view, c.node)
  proc begin_path*(c: Canvas) = ew_canvas_begin_path(c.view, c.node)
  proc move_to*(c: Canvas, x, y: float) = ew_canvas_move_to(c.view, c.node, x, y)
  proc line_to*(c: Canvas, x, y: float) = ew_canvas_line_to(c.view, c.node, x, y)
  proc quad_to*(c: Canvas, cx, cy, x, y: float) =
    ew_canvas_quad_to(c.view, c.node, cx, cy, x, y)
  proc cubic_to*(c: Canvas, c1x, c1y, c2x, c2y, x, y: float) =
    ew_canvas_cubic_to(c.view, c.node, c1x, c1y, c2x, c2y, x, y)
  proc close_path*(c: Canvas) = ew_canvas_close_path(c.view, c.node)
  proc fill*(c: Canvas, color: uint32) = ew_canvas_fill(c.view, c.node, color)
  proc stroke*(c: Canvas, color: uint32, width: float) =
    ew_canvas_stroke(c.view, c.node, color, width)
  proc fill_text*(c: Canvas, text: string, x, y, size: float, color: uint32, bold = false) =
    ew_canvas_fill_text(c.view, c.node, cstring(text), x, y, size.float32, color, bold)
  proc measure_text*(c: Canvas, text: string, size: float, bold = false): float =
    ew_measure_text(c.view, cstring(text), size.float32, bold)

proc text*(ui: Ui, tag, value: string): Elem =
  result = ui.element(tag)
  ui.set_text(result, value)
