## Prototype 5: a block tree for Enu scripts, converted to and from Nim
## source through Enu's nph fork (which keeps comments).
##
## Blocks are data. Leaf values (literals, names) and anything outside the
## happy-path subset are stored as source text, the way a block editor's text
## slots would hold them, and parsed again on the way back to code.

import std/[strutils, sequtils]
import "$nim"/compiler/idents
import phast, phparser, phrenderer, phlexer, phlineinfos, phoptions

type
  ExprKind* = enum
    LEAF ## a literal or a name, as text: `10`, `right`, `"hi"`
    INFIX ## `a + b`, `0 .. 360`
    PREFIX ## `-a`, `not a`
    CALL ## `f(a, b = c)`, or command style `f a, b`
    DOT ## `a.b`
    PAR ## `(a)`
    EXPR_CODE ## anything else, as text

  Expr* = ref object
    kind*: ExprKind
    text*: string ## LEAF/EXPR_CODE text, or the INFIX/PREFIX operator
    args*: seq[Expr] ## operands; for CALL the callee comes first
    names*: seq[string] ## CALL argument names; "" when positional
    command*: bool ## CALL written without parentheses

  BlockKind* = enum
    COMMAND ## a call statement: `forward 10`, `sphere(size = 4)`
    C_COMMAND ## a call with a body: `3.times(k):`, `forever:`
    ASSIGN ## `color = brown`, `y += 11`
    DECLARE ## `let x = 1`, `var door* = Door.new()`
    IF
    WHILE
    FOR
    PROC
    RETURN
    JUMP ## `break`, `continue`
    STATE ## an Enu state: `-wander do:`
    TRANSITION ## an Enu state change: `nil -> wander`, `(a, b) ==> greet`
    COMMENT ## a standalone comment line
    CODE ## anything else, as text

  Block* = ref object
    kind*: BlockKind
    call*: Expr ## COMMAND / C_COMMAND
    target*, value*: Expr ## ASSIGN / DECLARE / RETURN (value only)
    op*: string ## ASSIGN operator, or DECLARE keyword (let/var/const)
    type_text*: string ## DECLARE type annotation, "" when absent
    conds*: seq[Expr] ## IF branch conditions; WHILE condition; FOR iterable
    bodies*: seq[seq[Block]] ## one per condition, plus an `else` if longer
    vars*: seq[string] ## FOR loop variables
    name*, signature*: string ## PROC name and the rest of its header
    text*: string ## CODE / COMMENT source
    before*, after*: seq[Token] ## comments attached to the statement
    gap*: bool ## a blank line separates this block from the one above
    heads*: seq[seq[Token]] ## comments after each header's `:`, one per body

  Stats* = object
    blocks*, code*: int
    fallbacks*: seq[string] ## node kinds that became CODE

var
  cache = new_ident_cache()
  conf: ConfigRef
  source_lines: seq[string]

proc render*(n: PNode): string =
  ## Renders a node from the most recent `parse`. nph's renderer reads atoms
  ## back out of the source of file 0, so each parse gets a fresh config and
  ## nodes are rendered against the parse they came from.
  render_tree(n, conf, RenderOptions(max_line_len: 80, inline_trailing_string: true))

proc parse*(src: string): PNode =
  conf = new_config_ref()
  conf.error_max = int.high
  result = parse_string(src, cache, conf, "script.nim")
  source_lines = src.split('\n')
  doAssert conf.error_counter == 0, "parse failed:\n" & src

# --- AST -> blocks ---------------------------------------------------------

proc has_comments(n: PNode): bool =
  if n.prefix.len > 0 or n.mid.len > 0 or n.postfix.len > 0:
    return true
  if n.kind notin {nkCharLit .. nkTripleStrLit, nkIdent, nkCommentStmt, nkEmpty}:
    for child in n:
      if has_comments(child):
        return true

const LITERALS = {nkCharLit .. nkTripleStrLit, nkNilLit}

proc to_expr(n: PNode): Expr =
  case n.kind
  of nkIdent, LITERALS:
    result = Expr(kind: LEAF, text: render(n))
  of nkInfix:
    result = Expr(kind: INFIX, text: render(n[0]), args: @[to_expr(n[1]), to_expr(n[2])])
  of nkPrefix:
    result = Expr(kind: PREFIX, text: render(n[0]), args: @[to_expr(n[1])])
  of nkDotExpr:
    result = Expr(kind: DOT, args: @[to_expr(n[0]), to_expr(n[1])])
  of nkPar:
    if n.len == 1:
      result = Expr(kind: PAR, args: @[to_expr(n[0])])
    else:
      result = Expr(kind: EXPR_CODE, text: render(n))
  of nkCall, nkCommand:
    result = Expr(kind: CALL, command: n.kind == nkCommand, args: @[to_expr(n[0])])
    result.names.add ""
    for arg in n.sons[1 ..^ 1]:
      if arg.kind == nkExprEqExpr:
        result.names.add render(arg[0])
        result.args.add to_expr(arg[1])
      else:
        result.names.add ""
        result.args.add to_expr(arg)
  else:
    result = Expr(kind: EXPR_CODE, text: render(n))

proc to_blocks*(n: PNode, stats: var Stats): seq[Block]

proc code_block(n: PNode, stats: var Stats): Block =
  inc stats.code
  result = Block(kind: CODE, text: render(n))
  stats.fallbacks.add $n.kind & "\t" & result.text.split('\n')[0]

proc is_body(n: PNode): bool =
  n.kind == nkStmtList and n.prefix.len == 0 and n.mid.len == 0 and
    n.postfix.len == 0

proc to_block(n: PNode, stats: var Stats): Block =
  inc stats.blocks
  if n.kind == nkCommentStmt:
    return Block(kind: COMMENT, text: render(n))
  if n.mid.len > 0 and n.kind notin {nkWhileStmt, nkForStmt, nkCall, nkCommand}:
    return code_block(n, stats)

  # Comments on the statement itself travel with the block; comments
  # anywhere inside its expressions send the whole statement to CODE.
  let (before, after) = (n.prefix, n.postfix)
  n.prefix = @[]
  n.postfix = @[]

  template expr_ok(e: PNode): bool =
    not has_comments(e)

  case n.kind
  of nkCall, nkCommand:
    let last = n[^1]
    if last.kind == nkStmtList:
      if is_body(last) and n.sons[0 ..^ 2].all_it(expr_ok(it)):
        let head = new_node(n.kind)
        for son in n.sons[0 ..^ 2]:
          head.add son
        result = Block(
          kind: C_COMMAND,
          call: to_expr(head),
          bodies: @[to_blocks(last, stats)],
          heads: @[n.mid],
        )
    elif n.mid.len == 0 and n.sons.all_it(expr_ok(it)):
      result = Block(kind: COMMAND, call: to_expr(n))
  of nkAsgn:
    if expr_ok(n[0]) and expr_ok(n[1]):
      result = Block(kind: ASSIGN, op: "=", target: to_expr(n[0]), value: to_expr(n[1]))
  of nkInfix:
    let op = render(n[0])
    if op in ["+=", "-=", "*=", "/=", "&="] and expr_ok(n[1]) and expr_ok(n[2]):
      result = Block(kind: ASSIGN, op: op, target: to_expr(n[1]), value: to_expr(n[2]))
    elif op in ["->", "==>"] and n.len == 3 and expr_ok(n[1]) and expr_ok(n[2]):
      result = Block(kind: TRANSITION, op: op, target: to_expr(n[1]), value: to_expr(n[2]))
  of nkPrefix:
    if render(n[0]) == "-" and n.len == 3 and n[1].kind == nkIdent and is_body(n[2]):
      result = Block(kind: STATE, name: render(n[1]), bodies: @[to_blocks(n[2], stats)])
  of nkBreakStmt, nkContinueStmt:
    if n[0].kind == nkEmpty:
      result = Block(kind: JUMP, text: render(n))
  of nkLetSection, nkVarSection, nkConstSection:
    # A trailing comment lands on the IdentDefs; it belongs to the line.
    var trailing: seq[Token]
    if n.len == 1 and n[0].kind in {nkIdentDefs, nkConstDef}:
      trailing = n[0].postfix
      n[0].postfix = @[]
    if n.len == 1 and n[0].kind in {nkIdentDefs, nkConstDef} and n[0].len == 3 and
        (n[0][2].kind != nkEmpty or n[0][1].kind != nkEmpty) and expr_ok(n[0]):
      let keyword =
        case n.kind
        of nkLetSection: "let"
        of nkVarSection: "var"
        else: "const"
      result = Block(
        kind: DECLARE,
        op: keyword,
        target: Expr(kind: EXPR_CODE, text: render(n[0][0])),
        type_text: (if n[0][1].kind == nkEmpty: "" else: render(n[0][1])),
        value: (if n[0][2].kind == nkEmpty: nil else: to_expr(n[0][2])),
      )
      n.postfix.add trailing
    elif trailing.len > 0:
      n[0].postfix = trailing
  of nkIfStmt:
    var b = Block(kind: IF)
    for branch in n:
      if not is_body(branch[^1]) or branch.prefix.len + branch.postfix.len > 0:
        return code_block(n, stats)
      b.heads.add branch.mid
      if branch.kind == nkElifBranch:
        if not expr_ok(branch[0]):
          return code_block(n, stats)
        b.conds.add to_expr(branch[0])
      b.bodies.add to_blocks(branch[^1], stats)
    result = b
  of nkWhileStmt:
    if expr_ok(n[0]) and is_body(n[1]):
      result = Block(
        kind: WHILE, conds: @[to_expr(n[0])], bodies: @[to_blocks(n[1], stats)], heads: @[n.mid]
      )
  of nkForStmt:
    let vars = n.sons[0 ..^ 3]
    if vars.all_it(it.kind == nkIdent) and expr_ok(n[^2]) and is_body(n[^1]):
      result = Block(
        kind: FOR,
        vars: vars.map_it(render(it)),
        conds: @[to_expr(n[^2])],
        bodies: @[to_blocks(n[^1], stats)],
        heads: @[n.mid],
      )
  of nkProcDef:
    let body = n[^1]
    if body.kind == nkStmtList and is_body(body):
      n[^1] = new_node(nkEmpty)
      let text = render(n)
      let commented = has_comments(n)
      n[^1] = body
      if not commented:
        result = Block(
          kind: PROC,
          name: render(n[0]),
          signature: text.strip,
          bodies: @[to_blocks(body, stats)],
        )
  of nkReturnStmt:
    if expr_ok(n[0]):
      result = Block(kind: RETURN, value: (if n[0].kind == nkEmpty: nil else: to_expr(n[0])))
  else:
    discard

  if result.is_nil:
    result = code_block(n, stats)
  result.before = before
  result.after = after & (if result.kind == DECLARE: n.postfix else: @[])

proc gap_above(n: PNode): bool =
  let first_line = if n.prefix.len > 0: n.prefix[0].line else: n.info.line.int
  first_line >= 2 and source_lines[first_line - 2].strip == ""

proc to_blocks*(n: PNode, stats: var Stats): seq[Block] =
  assert n.kind == nkStmtList
  for i, child in n:
    let gap = i > 0 and gap_above(child)
    let b = to_block(child, stats)
    b.gap = gap
    result.add b

# --- blocks -> text -------------------------------------------------------
#
# Blocks print as plain source, which nph then formats. A block editor would
# do the same: it never needs to know nph's layout rules.

proc to_text*(e: Expr): string =
  case e.kind
  of LEAF, EXPR_CODE:
    result = e.text
  of INFIX:
    result = to_text(e.args[0]) & " " & e.text & " " & to_text(e.args[1])
  of PREFIX:
    let space = if e.text[0].is_alpha_ascii: " " else: ""
    result = e.text & space & to_text(e.args[0])
  of DOT:
    result = to_text(e.args[0]) & "." & to_text(e.args[1])
  of PAR:
    result = "(" & to_text(e.args[0]) & ")"
  of CALL:
    var args: seq[string]
    for i in 1 ..< e.args.len:
      let arg = to_text(e.args[i])
      args.add(if e.names[i] == "": arg else: e.names[i] & " = " & arg)
    let callee = to_text(e.args[0])
    if e.command:
      result = callee & " " & args.join(", ")
    else:
      result = callee & "(" & args.join(", ") & ")"

proc indent_lines(text: string, depth: int): string =
  let pad = repeat("  ", depth)
  # Lines inside a triple-quoted string are content, not code: leave them be.
  var in_string = false
  let lines: seq[string] = text.split('\n')
  for i, line in lines:
    if i > 0:
      result.add "\n"
    if line.len > 0 and not in_string:
      result.add pad
    result.add line
    if line.count("\"\"\"") mod 2 == 1:
      in_string = not in_string

proc to_text*(blocks: seq[Block], depth = 0): string

proc header_and_body(
    header: string, body: seq[Block], depth: int, comments: seq[Token] = @[]
): string =
  var line = header & ":"
  for c in comments:
    line.add " " & c.literal
  indent_lines(line, depth) & "\n" & to_text(body, depth + 1)

proc head(b: Block, i: int): seq[Token] =
  if i < b.heads.len: b.heads[i] else: @[]

proc to_text*(b: Block, depth: int): string =
  if b.gap:
    result.add "\n"
  for c in b.before:
    result.add indent_lines(c.literal, depth) & "\n"
  let line =
    case b.kind
    of COMMAND:
      indent_lines(to_text(b.call), depth)
    of C_COMMAND:
      header_and_body(to_text(b.call), b.bodies[0], depth, b.head(0))
    of ASSIGN:
      indent_lines(to_text(b.target) & " " & b.op & " " & to_text(b.value), depth)
    of DECLARE:
      let type_part = if b.type_text == "": "" else: ": " & b.type_text
      let value_part = if b.value.is_nil: "" else: " = " & to_text(b.value)
      indent_lines(b.op & " " & b.target.text & type_part & value_part, depth)
    of IF:
      var parts: seq[string]
      for i, body in b.bodies:
        let header =
          if i == 0: "if " & to_text(b.conds[0])
          elif i < b.conds.len: "elif " & to_text(b.conds[i])
          else: "else"
        parts.add header_and_body(header, body, depth, b.head(i))
      parts.join("\n")
    of WHILE:
      header_and_body("while " & to_text(b.conds[0]), b.bodies[0], depth, b.head(0))
    of FOR:
      header_and_body(
        "for " & b.vars.join(", ") & " in " & to_text(b.conds[0]),
        b.bodies[0],
        depth,
        b.head(0),
      )
    of PROC:
      header_and_body(b.signature & " =", b.bodies[0], depth).replace(" =:", " =")
    of RETURN:
      indent_lines("return" & (if b.value.is_nil: "" else: " " & to_text(b.value)), depth)
    of JUMP, COMMENT, CODE:
      indent_lines(b.text, depth)
    of STATE:
      header_and_body("-" & b.name & " do", b.bodies[0], depth)
    of TRANSITION:
      indent_lines(to_text(b.target) & " " & b.op & " " & to_text(b.value), depth)
  result.add line
  for c in b.after:
    result.add " " & c.literal

proc to_text*(blocks: seq[Block], depth = 0): string =
  blocks.map_it(to_text(it, depth)).join("\n")

proc to_source*(blocks: seq[Block]): string =
  ## Blocks back to formatted Nim.
  render(parse(to_text(blocks)))
