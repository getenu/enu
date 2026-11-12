## The `bake` blocks in a compiled module. Each `bake` expands to a
## `bake_begin(build, file, line, key, inputs, rebake, enu_key)` call whose
## site arguments are literals; collecting them lets the host drop recordings
## whose block is gone before the script runs.

import compiler/ast
type BakeSite* = tuple[file: string, line: int, key: string, enu: string]
  ## A `bake` block as compiled: where it is, its literal key ("" for a
  ## keyless one) and the Enu bake key it was compiled with.

const BAKE_BEGIN = "bake_begin"

proc literal_str(n: PNode): string =
  if n.kind in nkStrLit .. nkTripleStrLit: n.str_val else: ""

proc collect(n: PNode, sites: var seq[BakeSite]) =
  if n.is_nil:
    return
  if n.kind in nkCallKinds and n.len >= 8 and n[0].kind == nkSym and
      n[0].sym.name.s == BAKE_BEGIN and n[3].kind in nkCharLit .. nkUInt64Lit:
    sites.add (
      n[2].literal_str, n[3].int_val.int, n[4].literal_str, n[7].literal_str
    )
  for i in 0 ..< n.safe_len:
    collect(n[i], sites)

proc bake_sites*(n: PNode): seq[BakeSite] =
  ## Every `bake` block in a module's typed AST.
  collect(n, result)
