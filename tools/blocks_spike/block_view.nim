## Prototype 4: draw a block tree on a canvas, hit test it, and move blocks
## by dragging. Draws through web_ui's Canvas, so the same code targets
## Blitz natively or a browser canvas.
##
## The look follows the shared visual language of block editors (notched
## stack blocks, C-shaped loops, hats, rounded value slots, a color per
## category) with our own colors and proportions.

import std/[strutils, tables]
import blocks, web_ui

const
  FONT = 15.0
  ROW_H = 40.0
  SLOT_H = 26.0
  PAD = 10.0
  GAP = 6.0
  ARM = 22.0 ## bottom arm of a C block
  WALL = 18.0 ## left wall of a C block
  NOTCH_X = 14.0
  NOTCH_W = 22.0
  NOTCH_H = 5.0
  HAT_H = 14.0
  RADIUS = 5.0
  STACK_GAP = 36.0
  WHITE = 0xffffffff'u32
  INK = 0x2b2f3aff'u32

  MOTION = 0x4a8fe0ff'u32
  DRAWING = 0x9a6ad9ff'u32
  CONTROL = 0xeaa23aff'u32
  DATA = 0xe8783fff'u32
  STATES = 0xd9b52bff'u32
  PROCS = 0xdd6699ff'u32
  LOOKS = 0x52b06eff'u32
  CODE_COLOR = 0x737b88ff'u32
  NOTE = 0xfff1a8ff'u32

  MOTION_WORDS = ["forward", "back", "turn", "lean", "up", "down", "left", "right",
    "move", "go", "home", "near", "far"]
  DRAWING_WORDS = ["sphere", "box", "cylinder", "cube", "fill", "color", "scale",
    "speed", "pen", "draw", "erase", "lock", "glow"]
  LOOKS_WORDS = ["say", "show", "hide", "message", "open"]

type
  Hit* = object
    ## Where a block was drawn, so a pointer can find it again.
    b*: Block
    list*: ptr seq[Block]
    index*: int
    x*, y*, w*, h*: float

  View* = object
    c*: Canvas
    hits*: seq[Hit]

proc head_word(e: Expr): string =
  if e.is_nil:
    return ""
  case e.kind
  of LEAF: e.text
  of CALL, DOT: head_word(e.args[0])
  else: ""

proc color_of(b: Block): uint32 =
  case b.kind
  of IF, WHILE, FOR, JUMP, RETURN: CONTROL
  of DECLARE: DATA
  of STATE, TRANSITION: STATES
  of PROC: PROCS
  of COMMENT: NOTE
  of CODE: CODE_COLOR
  of ASSIGN:
    if head_word(b.target) in DRAWING_WORDS: DRAWING else: DATA
  of COMMAND, C_COMMAND:
    let word = head_word(b.call)
    if b.kind == C_COMMAND or word in ["times", "forever"]: CONTROL
    elif word in MOTION_WORDS: MOTION
    elif word in DRAWING_WORDS: DRAWING
    elif word in LOOKS_WORDS: LOOKS
    else: PROCS

proc darker(c: uint32): uint32 =
  let r = ((c shr 24) and 0xff) * 3 div 4
  let g = ((c shr 16) and 0xff) * 3 div 4
  let b = ((c shr 8) and 0xff) * 3 div 4
  (r shl 24) or (g shl 16) or (b shl 8) or 0xff

# --- inline content: labels and value slots --------------------------------

type Piece = object
  label: string ## plain words on the block
  expr: Expr ## or a value slot

proc text_w(v: View, s: string, bold = false): float =
  v.c.measure_text(s, FONT, bold)

proc short(s: string, n = 38): string =
  let flat = s.replace("\n", " ")
  if flat.len > n: flat[0 ..< n - 1] & "…" else: flat

proc slot_w(v: View, e: Expr): float

proc pieces_w(v: View, pieces: seq[Piece]): float =
  for i, p in pieces:
    if i > 0:
      result += GAP
    result += (if p.expr.is_nil: v.text_w(p.label, true) else: v.slot_w(p.expr))

proc call_pieces(e: Expr): seq[Piece] =
  ## `forward 10` -> [forward][10]; `sphere(size = d)` -> [sphere][size][d]
  result.add Piece(label: to_text(e.args[0]))
  for i in 1 ..< e.args.len:
    if e.names[i] != "":
      result.add Piece(label: e.names[i])
    result.add Piece(expr: e.args[i])

proc reporter_pieces(e: Expr): seq[Piece] =
  case e.kind
  of INFIX:
    @[Piece(expr: e.args[0]), Piece(label: e.text), Piece(expr: e.args[1])]
  of PREFIX:
    @[Piece(label: e.text), Piece(expr: e.args[0])]
  of CALL:
    call_pieces(e)
  of DOT:
    @[Piece(expr: e.args[0]), Piece(label: "." & to_text(e.args[1]))]
  else:
    @[]

proc is_plain(e: Expr): bool =
  ## Shown as text in a white slot rather than as a nested reporter.
  case e.kind
  of LEAF, EXPR_CODE: true
  of DOT: is_plain(e.args[0]) and is_plain(e.args[1])
  of PAR: is_plain(e.args[0])
  else: false

proc slot_w(v: View, e: Expr): float =
  if e.kind == PAR:
    return v.slot_w(e.args[0])
  if is_plain(e):
    return v.text_w(short(to_text(e))) + 2 * PAD
  v.pieces_w(reporter_pieces(e)) + 2 * PAD

proc pill(v: View, x, y, w, h: float, color: uint32) =
  let r = h / 2
  let c = v.c
  c.begin_path()
  c.move_to(x + r, y)
  c.line_to(x + w - r, y)
  c.quad_to(x + w, y, x + w, y + r)
  c.quad_to(x + w, y + h, x + w - r, y + h)
  c.line_to(x + r, y + h)
  c.quad_to(x, y + h, x, y + r)
  c.quad_to(x, y, x + r, y)
  c.close_path()
  c.fill(color)

proc draw_pieces(v: View, pieces: seq[Piece], x, mid: float, ink: uint32, bg: uint32)

proc draw_slot(v: View, e: Expr, x, mid: float, bg: uint32): float =
  ## Draws a value slot centred on `mid`; returns its width.
  if e.kind == PAR:
    return v.draw_slot(e.args[0], x, mid, bg)
  result = v.slot_w(e)
  if is_plain(e):
    v.pill(x, mid - SLOT_H / 2, result, SLOT_H, WHITE)
    v.c.fill_text(short(to_text(e)), x + PAD, mid + FONT * 0.35, FONT, INK)
  else:
    v.pill(x, mid - SLOT_H / 2 - 2, result, SLOT_H + 4, darker(bg))
    v.draw_pieces(reporter_pieces(e), x + PAD, mid, WHITE, darker(bg))

proc draw_pieces(v: View, pieces: seq[Piece], x, mid: float, ink: uint32, bg: uint32) =
  var x = x
  for p in pieces:
    if p.expr.is_nil:
      v.c.fill_text(p.label, x, mid + FONT * 0.35, FONT, ink, true)
      x += v.text_w(p.label, true) + GAP
    else:
      x += v.draw_slot(p.expr, x, mid, bg) + GAP

proc header_pieces(b: Block, branch = 0): seq[Piece] =
  case b.kind
  of COMMAND, C_COMMAND:
    let e = b.call
    if e.kind == CALL:
      # `3.times(k):` reads better as "repeat [3] times as k"
      if e.args[0].kind == DOT and to_text(e.args[0].args[1]) == "times":
        result = @[Piece(label: "repeat"), Piece(expr: e.args[0].args[0]), Piece(label: "times")]
        if e.args.len > 1:
          result.add Piece(label: "as")
          result.add Piece(expr: e.args[1])
      else:
        result = call_pieces(e)
    else:
      result = @[Piece(expr: e)]
  of ASSIGN:
    let verb = if b.op == "=": "set" else: "change by " & b.op[0]
    result = @[Piece(label: verb), Piece(expr: b.target), Piece(label: "to"), Piece(expr: b.value)]
    if b.op != "=":
      result = @[Piece(label: "change"), Piece(expr: b.target), Piece(label: "by " & b.op[0 .. 0]),
        Piece(expr: b.value)]
  of DECLARE:
    result = @[Piece(label: b.op), Piece(label: b.target.text)]
    if b.type_text != "":
      result.add Piece(label: ": " & b.type_text)
    if not b.value.is_nil:
      result.add Piece(label: "=")
      result.add Piece(expr: b.value)
  of IF:
    if branch == 0:
      result = @[Piece(label: "if"), Piece(expr: b.conds[0])]
    elif branch < b.conds.len:
      result = @[Piece(label: "else if"), Piece(expr: b.conds[branch])]
    else:
      result = @[Piece(label: "else")]
  of WHILE:
    result = @[Piece(label: "while"), Piece(expr: b.conds[0])]
  of FOR:
    result = @[Piece(label: "for each"), Piece(label: b.vars.join(", ")), Piece(label: "in"),
      Piece(expr: b.conds[0])]
  of PROC:
    result = @[Piece(label: "define"), Piece(label: short(b.signature.replace("proc ", ""), 44))]
  of STATE:
    result = @[Piece(label: "when"), Piece(label: b.name)]
  of TRANSITION:
    result = @[Piece(expr: b.target), Piece(label: if b.op == "->": "then" else: "then, when done,"),
      Piece(expr: b.value)]
  of RETURN:
    result = @[Piece(label: "return")]
    if not b.value.is_nil:
      result.add Piece(expr: b.value)
  of JUMP:
    result = @[Piece(label: if b.text == "break": "stop loop" else: "next")]
  of COMMENT:
    result = @[Piece(label: short(b.text.strip(chars = {'#', ' '}), 60))]
  of CODE:
    result = @[Piece(label: short(b.text, 60))]

# --- shapes ----------------------------------------------------------------

proc stack_top(c: Canvas, x, y, w: float, hat: bool) =
  ## Moves along the top edge, leaving the notch other blocks snap into.
  if hat:
    c.move_to(x, y + HAT_H)
    c.cubic_to(x + 25, y - 4, x + 70, y - 4, x + 95, y + HAT_H)
    c.line_to(x + w - RADIUS, y + HAT_H)
    c.quad_to(x + w, y + HAT_H, x + w, y + HAT_H + RADIUS)
  else:
    c.move_to(x, y + RADIUS)
    c.quad_to(x, y, x + RADIUS, y)
    c.line_to(x + NOTCH_X, y)
    c.line_to(x + NOTCH_X + 4, y + NOTCH_H)
    c.line_to(x + NOTCH_X + NOTCH_W - 4, y + NOTCH_H)
    c.line_to(x + NOTCH_X + NOTCH_W, y)
    c.line_to(x + w - RADIUS, y)
    c.quad_to(x + w, y, x + w, y + RADIUS)

proc tab_edge(c: Canvas, x_right, x_left, y: float) =
  ## Bottom edge from right to left with the tab that fills the next notch.
  c.line_to(x_left + NOTCH_X + NOTCH_W, y)
  c.line_to(x_left + NOTCH_X + NOTCH_W - 4, y + NOTCH_H)
  c.line_to(x_left + NOTCH_X + 4, y + NOTCH_H)
  c.line_to(x_left + NOTCH_X, y)
  c.line_to(x_left + RADIUS, y)

proc stack_shape(v: View, x, y, w, h: float, color: uint32, hat = false) =
  let c = v.c
  c.begin_path()
  stack_top(c, x, y, w, hat)
  c.line_to(x + w, y + h - RADIUS)
  c.quad_to(x + w, y + h, x + w - RADIUS, y + h)
  tab_edge(c, x + w, x, y + h)
  c.quad_to(x, y + h, x, y + h - RADIUS)
  c.close_path()
  c.fill(color)
  c.stroke(darker(color), 1)

# --- layout + drawing ------------------------------------------------------

proc height_of(v: View, blocks: seq[Block]): float
proc draw_list(v: var View, blocks: var seq[Block], x, y: float): float

proc header_h(b: Block): float =
  (if b.kind in {STATE, PROC}: ROW_H + HAT_H else: ROW_H)

proc block_w(v: View, b: Block): float =
  var w = 0.0
  let branches = if b.kind == IF: b.bodies.len else: 1
  for i in 0 ..< branches:
    w = max(w, v.pieces_w(header_pieces(b, i)))
  max(w + 2 * PAD, 80)

proc height_of(v: View, b: Block): float =
  case b.kind
  of C_COMMAND, WHILE, FOR, STATE, PROC:
    result = header_h(b) + max(v.height_of(b.bodies[0]), 24) + ARM
  of IF:
    for body in b.bodies:
      result += ROW_H + max(v.height_of(body), 24)
    result += ARM
  else:
    result = ROW_H

proc height_of(v: View, blocks: seq[Block]): float =
  for b in blocks:
    result += v.height_of(b)

proc draw_block(v: var View, list: var seq[Block], index: int, x, y: float): float =
  let b = list[index]
  let color = color_of(b)
  let ink = if b.kind in {COMMENT, STATE, TRANSITION}: INK else: WHITE
  let w = v.block_w(b)
  result = v.height_of(b)
  v.hits.add Hit(b: b, list: list.addr, index: index, x: x, y: y, w: w, h: result)

  if b.kind in {C_COMMAND, WHILE, FOR, STATE, PROC, IF}:
    # One shape: header arms on the right, a wall on the left, a bottom arm.
    let hat = b.kind in {STATE, PROC}
    var arms: seq[(float, float)] # (top, height) of each arm
    var y_cursor = y
    let branches = b.bodies.len
    for i in 0 ..< branches:
      let hh = if i == 0: header_h(b) else: ROW_H
      arms.add (y_cursor, hh)
      y_cursor += hh + max(v.height_of(b.bodies[i]), 24)
    let bottom = y_cursor + ARM

    let c = v.c
    c.begin_path()
    stack_top(c, x, y, w, hat)
    for i, (top, hh) in arms:
      if i > 0:
        # back out of the previous mouth onto this arm
        c.line_to(x + WALL + RADIUS, top)
        c.line_to(x + w - RADIUS, top)
        c.quad_to(x + w, top, x + w, top + RADIUS)
      c.line_to(x + w, top + hh - RADIUS)
      c.quad_to(x + w, top + hh, x + w - RADIUS, top + hh)
      tab_edge(c, x + w, x + WALL, top + hh)
      c.line_to(x + WALL, top + hh)
      let next_top = if i + 1 < arms.len: arms[i + 1][0] else: y_cursor
      c.line_to(x + WALL, next_top)
    c.line_to(x + w - RADIUS, y_cursor)
    c.quad_to(x + w, y_cursor, x + w, y_cursor + RADIUS)
    c.line_to(x + w, bottom - RADIUS)
    c.quad_to(x + w, bottom, x + w - RADIUS, bottom)
    tab_edge(c, x + w, x, bottom)
    c.quad_to(x, bottom, x, bottom - RADIUS)
    c.close_path()
    c.fill(color)
    c.stroke(darker(color), 1)

    for i, (top, hh) in arms:
      let mid = top + hh - ROW_H / 2
      v.draw_pieces(header_pieces(b, i), x + PAD, mid, ink, color)
      discard v.draw_list(b.bodies[i], x + WALL, top + hh)
  else:
    v.stack_shape(x, y, w, ROW_H, color)
    v.draw_pieces(header_pieces(b), x + PAD, y + ROW_H / 2, ink, color)

proc draw_list(v: var View, blocks: var seq[Block], x, y: float): float =
  var y = y
  for i in 0 ..< blocks.len:
    y += v.draw_block(blocks, i, x, y)
  y

proc draw_script*(v: var View, blocks: var seq[Block], x, y: float): float =
  ## Top-level blocks; a blank line in the source starts a new stack.
  v.c.clear()
  v.hits.set_len(0)
  var y = y
  for i in 0 ..< blocks.len:
    if i > 0 and blocks[i].gap:
      y += STACK_GAP
    y += v.draw_block(blocks, i, x, y)
  y

proc script_height*(v: View, blocks: seq[Block]): float =
  for i, b in blocks:
    if i > 0 and b.gap:
      result += STACK_GAP
    result += v.height_of(b)

proc hit*(v: View, x, y: float): int =
  ## The innermost block under a point, as an index into `hits`, or -1.
  result = -1
  for i, h in v.hits:
    if x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + ROW_H:
      result = i # later hits are nested deeper

proc drop_target*(v: View, x, y: float): int =
  ## The block whose bottom edge is nearest a dropped block's top-left
  ## corner, within snapping range, or -1.
  result = -1
  var best = 40.0
  for i, h in v.hits:
    let d = abs(h.x - x) + abs(h.y + h.h - y)
    if d < best:
      best = d
      result = i
