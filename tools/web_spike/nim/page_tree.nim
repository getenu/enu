## Declarative pages, host side. A script describes its whole page on every
## pass (`page board: ...`); this compares the description with the last one
## and applies only the differences to the Blitz document. The differences
## are also kept as a list of edits, which is what other players would replay
## to keep a copy of the page.
##
## Nodes are identified by their path: the index of each node among its
## parent's children, joined with dots ("2.0.1"). Clicks are matched to
## elements by path, so a script can ask "was the element at this spot
## clicked?" while it describes the page.

import std/[tables, strutils]
import enu_web

const
  TOKEN_SEP* = '\x1e'
  FIELD_SEP* = '\x1f'

type
  VNode* = ref object
    tag*: string ## "" for text
    text*: string
    attrs*: seq[(string, string)]
    kids*: seq[VNode]
    node*: NodeId
    path*: string

  PageTree* = object
    root*: VNode
    paths: Table[uint64, string]
    edits*: seq[string]

proc parse_tree*(s: string): seq[VNode] =
  ## Reads the tokens a script sends: `E tag` opens an element, `A name
  ## value` sets an attribute on it, `T text` adds text, `C` closes.
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
    of "A":
      stack[^1].attrs.add (fields[1], fields[2])
    of "T":
      stack[^1].kids.add VNode(text: fields[1])
    of "C":
      if stack.len > 1:
        discard stack.pop
    else:
      discard
  stack[0].kids

proc child_path(parent: string, i: int): string =
  if parent == "": $i else: parent & "." & $i

proc describe(n: VNode): string =
  if n.tag == "": "text" else: n.tag

proc build(t: var PageTree, view: ViewPtr, n: VNode, path: string): NodeId =
  n.path = path
  if n.tag == "":
    n.node = ew_create_text(view, n.text.cstring)
  else:
    n.node = ew_create_element(view, n.tag.cstring)
    for (k, v) in n.attrs:
      ew_set_attribute(view, n.node, k.cstring, v.cstring)
    for i, kid in n.kids:
      ew_append(view, n.node, t.build(view, kid, child_path(path, i)))
  n.node

proc patch_children(t: var PageTree, view: ViewPtr, old, new: VNode)

proc patch(t: var PageTree, view: ViewPtr, old, new: VNode) =
  ## `old` and `new` are the same kind of node at the same spot.
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

proc patch_children(t: var PageTree, view: ViewPtr, old, new: VNode) =
  for i, kid in new.kids:
    let path = child_path(new.path, i)
    kid.path = path
    if i < old.kids.len:
      let was = old.kids[i]
      if was.tag == kid.tag:
        t.patch(view, was, kid)
      else:
        let node = t.build(view, kid, path)
        ew_insert_before(view, was.node, node)
        ew_remove(view, was.node)
        t.edits.add "replace " & path & " " & kid.describe
    else:
      ew_append(view, new.node, t.build(view, kid, path))
      t.edits.add "add " & path & " " & kid.describe
  for i in new.kids.len ..< old.kids.len:
    ew_remove(view, old.kids[i].node)
    t.edits.add "remove " & child_path(new.path, i)

proc index(t: var PageTree, n: VNode) =
  t.paths[n.node.uint64] = n.path
  for kid in n.kids:
    t.index(kid)

proc render*(t: var PageTree, view: ViewPtr, container: NodeId, kids: seq[VNode]): bool =
  ## Makes `container`'s children match `kids`. True if anything changed.
  let before = t.edits.len
  let new_root = VNode(tag: "div", node: container, kids: kids)
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
  ## The path of `node`, or of the nearest rendered element around it.
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
    if found and (p == path or p.starts_with(path & ".")):
      inc result

proc take_edits*(t: var PageTree): seq[string] =
  result = t.edits
  t.edits.set_len(0)
