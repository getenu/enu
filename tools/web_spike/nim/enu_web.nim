## Nim bindings for the enu_web C interface (see ../src/lib.rs).

import std/os

const ew_profile {.strdefine.} = "release"
const lib_dir = current_source_path.parent_dir / ".." / "target" / ew_profile

{.passl: lib_dir / "libenu_web.a".}
when defined(macosx):
  {.
    passl:
      "-framework CoreFoundation -framework CoreText -framework CoreGraphics " &
      "-framework Foundation -framework AppKit -framework Security"
  .}

type
  ViewPtr* = distinct pointer
  FramePtr* = distinct pointer
  NodeId* = distinct uint64

const
  NO_NODE* = NodeId(0)
  POINTER_MOVE* = 0'u32
  POINTER_DOWN* = 1'u32
  POINTER_UP* = 2'u32
  POINTER_LEAVE* = 3'u32

proc `==`*(a, b: NodeId): bool {.borrow.}
proc is_nil*(f: FramePtr): bool = f.pointer.is_nil

{.push importc, cdecl.}
proc ew_view_new*(html: cstring, width, height: uint32, scale: float32): ViewPtr
proc ew_view_free*(v: ViewPtr)
proc ew_set_html*(v: ViewPtr, html: cstring)
proc ew_resize*(v: ViewPtr, width, height: uint32)
proc ew_render*(v: ViewPtr): ptr UncheckedArray[uint8]
proc ew_content_height*(v: ViewPtr): float32
proc ew_query*(v: ViewPtr, selector: cstring): NodeId
proc ew_create_element*(v: ViewPtr, tag: cstring): NodeId
proc ew_create_text*(v: ViewPtr, text: cstring): NodeId
proc ew_set_attribute*(v: ViewPtr, node: NodeId, name, value: cstring)
proc ew_set_text*(v: ViewPtr, node: NodeId, text: cstring)
proc ew_set_inner_html*(v: ViewPtr, node: NodeId, html: cstring)
proc ew_append*(v: ViewPtr, parent, child: NodeId)
proc ew_insert_before*(v: ViewPtr, anchor, node: NodeId)
proc ew_remove_attribute*(v: ViewPtr, node: NodeId, name: cstring)
proc ew_remove*(v: ViewPtr, node: NodeId)
proc ew_parent*(v: ViewPtr, node: NodeId): NodeId
proc ew_element_at*(v: ViewPtr, x, y: float32): NodeId
proc ew_get_attribute*(
  v: ViewPtr, node: NodeId, name: cstring, buf: ptr char, len: csize_t
): int64
proc ew_write_png*(v: ViewPtr, path: cstring): bool
proc ew_get_text*(v: ViewPtr, node: NodeId): cstring
proc ew_rect*(v: ViewPtr, node: NodeId, out_rect: ptr array[4, float32])
proc ew_pointer*(
  v: ViewPtr, kind: uint32, x, y: float32, changed: ptr bool
): NodeId

# Pages that live on one thread and are shown on another (see ../src/hub.rs).
proc ew_present*(v: ViewPtr, key: cstring): float32
proc ew_take_frame*(key: cstring, since: uint64, version: ptr uint64): FramePtr
proc ew_frame_width*(f: FramePtr): uint32
proc ew_frame_height*(f: FramePtr): uint32
proc ew_frame_render_ms*(f: FramePtr): float32
proc ew_frame_pixels*(f: FramePtr): ptr UncheckedArray[uint8]
proc ew_frame_free*(f: FramePtr)
proc ew_post_pointer*(key: cstring, kind: uint32, u, v: float32): bool
proc ew_take_pointer*(key: cstring, out_events: ptr float32, max: csize_t): csize_t
proc ew_forget*(key: cstring)

# Every call catches its own panics (see ../src/guard.rs).
proc ew_take_error*(): cstring

proc ew_canvas_attach*(v: ViewPtr, node: NodeId)
proc ew_canvas_clear*(v: ViewPtr, node: NodeId)
proc ew_canvas_begin_path*(v: ViewPtr, node: NodeId)
proc ew_canvas_move_to*(v: ViewPtr, node: NodeId, x, y: float)
proc ew_canvas_line_to*(v: ViewPtr, node: NodeId, x, y: float)
proc ew_canvas_quad_to*(v: ViewPtr, node: NodeId, cx, cy, x, y: float)
proc ew_canvas_cubic_to*(v: ViewPtr, node: NodeId, c1x, c1y, c2x, c2y, x, y: float)
proc ew_canvas_close_path*(v: ViewPtr, node: NodeId)
proc ew_canvas_fill*(v: ViewPtr, node: NodeId, color: uint32)
proc ew_canvas_stroke*(v: ViewPtr, node: NodeId, color: uint32, width: float)
proc ew_canvas_fill_text*(
  v: ViewPtr, node: NodeId, text: cstring, x, y: float, size: float32, color: uint32,
  bold: bool,
)
proc ew_measure_text*(v: ViewPtr, text: cstring, size: float32, bold: bool): float32
{.pop.}

proc get_attribute*(v: ViewPtr, node: NodeId, name: string): string =
  ## Empty if absent.
  var buf: array[256, char]
  let n = ew_get_attribute(v, node, name.cstring, buf[0].addr, buf.len.csize_t)
  if n < 0:
    return ""
  if n < buf.len:
    return $cast[cstring](buf[0].addr)
  result = new_string(n)
  discard ew_get_attribute(v, node, name.cstring, result[0].addr, csize_t(n + 1))

proc take_error*(): string =
  ## The error from the last call that failed on this thread, or "". Clears
  ## it.
  let e = ew_take_error()
  if not e.is_nil:
    result = $e
