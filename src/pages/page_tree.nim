## Declarative pages, host side. A script describes its whole page on every
## pass (`page board: ...`); this compares the description with the last one
## and applies only the differences to the Blitz document. The differences
## are also kept as a list of edits, which is what other players would replay
## to keep a copy of the page.
##
## Elements with a key (their `id`, or one the script's loop gave them) are
## matched by key wherever they move. Others are matched by position. As in
## Karax, an unchanged run at the start and end of each child list is skipped
## first, so adding or removing one item doesn't disturb the rest.
##
## Paths name nodes for clicks and edits: one step per level, the node's key
## as `#key` if it has one, else its index among its siblings ("3/#bot_rat/0").
## The script computes the same paths while it describes the page, so a click
## is matched to the element the player actually clicked.

import std/[tables, strutils]
import renderer

const
  TOKEN_SEP* = '\x1e'
  FIELD_SEP* = '\x1f'

type
  VNode* = ref object
    tag*: string ## "" for text
    text*: string
    key*: string
    attrs*: seq[(string, string)]
    kids*: seq[VNode]
    node*: NodeId
    path*: string

  PageTree* = object
    root*: VNode
    paths: Table[uint64, string]
    edits*: seq[string]

proc parse_tree*(s: string): seq[VNode] =
  ## Reads the tokens a script sends: `E tag` opens an element, `K key` gives
  ## it a key, `A name value` sets an attribute (`id` is also its key), `T
  ## text` adds text, `C` closes.
  var stack = @[VNode()]
  for token in s.split(TOKEN_SEP):
    if token.len == 0:
      continue
    let fields = token.split(FIELD_SEP)
    case fields[0]
    of "E":
      let n = VNode(tag: fields[1])
      stack[^1].kids.add n
      stack.add n
    of "K":
      if stack[^1].key == "":
        stack[^1].key = fields[1]
    of "A":
      stack[^1].attrs.add (fields[1], fields[2])
      if fields[1] == "id":
        stack[^1].key = fields[2]
    of "T":
      stack[^1].kids.add VNode(text: fields[1])
    of "C":
      if stack.len > 1:
        discard stack.pop
    else:
      discard
  stack[0].kids

proc child_path(parent: string, n: VNode, i: int): string =
  let step = if n.key != "": "#" & n.key else: $i
  if parent == "": step else: parent & "/" & step

proc describe(n: VNode): string =
  if n.tag == "": "text" else: n.tag

proc identical(a, b: VNode): bool =
  if a.tag != b.tag or a.key != b.key or a.text != b.text or
      a.attrs != b.attrs or a.kids.len != b.kids.len:
    return false
  for i in 0 ..< a.kids.len:
    if not identical(a.kids[i], b.kids[i]):
      return false
  true

proc same_kids*(a, b: seq[VNode]): bool =
  ## Whether two descriptions are the same, without needing a document.
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    if not identical(a[i], b[i]):
      return false
  true

proc same_end(a, b: VNode): bool =
  ## Whether `a` and `b` can be paired while skipping the unchanged start and
  ## end of a child list: the same key, or no keys and nothing changed.
  if a.key != "" or b.key != "":
    a.key == b.key and a.tag == b.tag
  else:
    identical(a, b)

proc assign_paths(n: VNode, path: string) =
  n.path = path
  for i, kid in n.kids:
    kid.assign_paths(child_path(path, kid, i))

proc build(t: var PageTree, view: ViewPtr, n: VNode): NodeId =
  if n.tag == "":
    n.node = ew_create_text(view, n.text.cstring)
  else:
    n.node = ew_create_element(view, n.tag.cstring)
    for (k, v) in n.attrs:
      ew_set_attribute(view, n.node, k.cstring, v.cstring)
    for kid in n.kids:
      ew_append(view, n.node, t.build(view, kid))
  n.node

proc place(view: ViewPtr, parent, node, before: NodeId) =
  if before == NO_NODE:
    ew_append(view, parent, node)
  else:
    ew_insert_before(view, before, node)

proc patch_children(t: var PageTree, view: ViewPtr, old, new: VNode) {.gcsafe.}

proc patch(t: var PageTree, view: ViewPtr, old, new: VNode) =
  ## `old` and `new` are the same element (or text) in two descriptions.
  new.node = old.node
  if new.tag == "":
    if new.text != old.text:
      ew_set_text(view, new.node, new.text.cstring)
      t.edits.add "text " & new.path & " " & new.text
    return
  for (k, v) in new.attrs:
    var same = false
    for (ok, ov) in old.attrs:
      if ok == k:
        same = ov == v
        break
    if not same:
      ew_set_attribute(view, new.node, k.cstring, v.cstring)
      t.edits.add "attr " & new.path & " " & k & "=" & v
  for (ok, _) in old.attrs:
    var kept = false
    for (k, _) in new.attrs:
      if k == ok:
        kept = true
        break
    if not kept:
      ew_remove_attribute(view, new.node, ok.cstring)
      t.edits.add "unattr " & new.path & " " & ok
  t.patch_children(view, old, new)

proc longest_increasing(values: seq[int]): seq[bool] =
  ## Marks the longest increasing run of `values` (skipping -1s). Those
  ## elements are already in order and don't need to move.
  result = new_seq[bool](values.len)
  var tails: seq[int] # index into values of the last item of each run length
  var before = new_seq[int](values.len)
  for i, v in values:
    if v < 0:
      continue
    var lo = 0
    var hi = tails.len
    while lo < hi:
      let mid = (lo + hi) div 2
      if values[tails[mid]] < v: lo = mid + 1 else: hi = mid
    before[i] = if lo > 0: tails[lo - 1] else: -1
    if lo == tails.len: tails.add i else: tails[lo] = i
  if tails.len > 0:
    var i = tails[^1]
    while i >= 0:
      result[i] = true
      i = before[i]

proc patch_children(t: var PageTree, view: ViewPtr, old, new: VNode) {.gcsafe.} =
  let (ol, nl) = (old.kids.len, new.kids.len)
  var start = 0
  while start < ol and start < nl and same_end(old.kids[start], new.kids[start]):
    t.patch(view, old.kids[start], new.kids[start])
    inc start
  var tail = 0
  while tail < ol - start and tail < nl - start and
      same_end(old.kids[ol - 1 - tail], new.kids[nl - 1 - tail]):
    t.patch(view, old.kids[ol - 1 - tail], new.kids[nl - 1 - tail])
    inc tail

  # The changed middle: match by key, or by position among unkeyed nodes.
  let old_mid = old.kids[start ..< ol - tail]
  let new_mid = new.kids[start ..< nl - tail]
  var by_key: Table[string, int]
  var unkeyed: seq[int]
  for i, o in old_mid:
    if o.key != "": by_key[o.key] = i else: unkeyed.add i
  var matched = new_seq[int](new_mid.len)
  var used = new_seq[bool](old_mid.len)
  var u = 0
  for j, n in new_mid:
    matched[j] = -1
    if n.key != "":
      let i = by_key.get_or_default(n.key, -1)
      if i >= 0 and not used[i] and old_mid[i].tag == n.tag:
        matched[j] = i
        used[i] = true
    elif u < unkeyed.len:
      let i = unkeyed[u]
      inc u
      if old_mid[i].tag == n.tag:
        matched[j] = i
        used[i] = true
  for i, o in old_mid:
    if not used[i]:
      ew_remove(view, o.node)
      t.edits.add "remove " & o.path

  # Put the middle in order, right to left, moving only what's out of order.
  let stay = longest_increasing(matched)
  var before = if tail > 0: new.kids[nl - tail].node else: NO_NODE
  for j in countdown(new_mid.high, 0):
    let n = new_mid[j]
    if matched[j] >= 0:
      t.patch(view, old_mid[matched[j]], n)
      if not stay[j]:
        place(view, new.node, n.node, before)
        t.edits.add "move " & n.path
    else:
      place(view, new.node, t.build(view, n), before)
      t.edits.add "add " & n.path & " " & n.describe
    before = n.node

proc index(t: var PageTree, n: VNode) =
  t.paths[n.node.uint64] = n.path
  for kid in n.kids:
    t.index(kid)

proc render*(t: var PageTree, view: ViewPtr, container: NodeId, kids: seq[VNode]): bool =
  ## Makes `container`'s children match `kids`. True if anything changed.
  let before = t.edits.len
  let new_root = VNode(tag: "div", node: container, kids: kids)
  new_root.assign_paths("")
  let old_root =
    if t.root.is_nil or t.root.node != container:
      VNode(tag: "div", node: container)
    else:
      t.root
  t.patch_children(view, old_root, new_root)
  t.root = new_root
  t.paths.clear
  t.index(new_root)
  t.paths.del container.uint64
  t.edits.len > before

proc path_of(t: PageTree, view: ViewPtr, node: NodeId, found: var bool): string =
  ## The path of `node`, or of the nearest described element around it.
  var n = node
  while n != NO_NODE:
    if n.uint64 in t.paths:
      found = true
      return t.paths[n.uint64]
    n = ew_parent(view, n)

proc clicks_at*(t: PageTree, view: ViewPtr, targets: seq[int], path: string): int =
  ## How many of `targets` (clicked nodes) are the element at `path` or
  ## inside it.
  for target in targets:
    var found = false
    let p = t.path_of(view, NodeId(target), found)
    if found and (p == path or p.starts_with(path & "/")):
      inc result

proc take_edits*(t: var PageTree): seq[string] =
  result = t.edits
  t.edits.set_len(0)
