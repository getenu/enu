## Declarative pages against a real Blitz document: only the differences are
## applied, they're logged as edits, and clicks are matched by path.

import std/strutils
import enu_web, page_tree

proc e(tag: string): string = "E" & FIELD_SEP & tag & TOKEN_SEP
proc a(k, v: string): string = "A" & FIELD_SEP & k & FIELD_SEP & v & TOKEN_SEP
proc t(text: string): string = "T" & FIELD_SEP & text & TOKEN_SEP
const c = "C" & TOKEN_SEP

proc counter(count: int, items = 0, title = "h2"): string =
  result = e(title) & t("Counter") & c
  result &= e("p") & t("Count: ") & e("b") & t($count) & c & c
  result &= e("button") & a("id", "add") & t("Add one") & c
  result &= e("ul")
  for i in 1 .. items:
    result &= e("li") & t("item " & $i) & c
  result &= c

let v = ew_view_new("<div id=root></div>", 600, 400, 1.0)
let root = ew_query(v, "#root")
var tree: PageTree

doAssert tree.render(v, root, parse_tree(counter(0)))
discard tree.take_edits
doAssert $ew_get_text(v, root) == "CounterCount: 0Add one"

doAssert not tree.render(v, root, parse_tree(counter(0))), "nothing changed"

doAssert tree.render(v, root, parse_tree(counter(1)))
let edits = tree.take_edits
doAssert edits == @["text 1.1.0 1"], $edits
doAssert $ew_get_text(v, root) == "CounterCount: 1Add one"

discard tree.render(v, root, parse_tree(counter(1, items = 2)))
doAssert tree.take_edits == @["add 3.0 li", "add 3.1 li"]
discard tree.render(v, root, parse_tree(counter(1, items = 1)))
doAssert tree.take_edits == @["remove 3.1"]
discard tree.render(v, root, parse_tree(counter(1, items = 1, title = "h3")))
doAssert tree.take_edits == @["replace 0 h3"]
doAssert $ew_get_text(v, root) == "CounterCount: 1Add oneitem 1"

# Attributes: change, then drop.
let base = counter(1, items = 1, title = "h3")
let with_class = base.replace(a("id", "add"), a("id", "add") & a("class", "big"))
discard tree.render(v, root, parse_tree(with_class))
var got = tree.take_edits
doAssert got == @["attr 2 class=big"], $got
discard tree.render(v, root, parse_tree(base))
got = tree.take_edits
doAssert got == @["unattr 2 class"], $got

# Clicks are matched to elements by path, including clicks on their text.
var r: array[4, float32]
let button = ew_query(v, "#add")
ew_rect(v, button, r.addr)
let target = ew_element_at(v, r[0] + r[2] / 2, r[1] + r[3] / 2)
doAssert target != NO_NODE
let targets = @[int(target.uint64)]
doAssert tree.clicks_at(v, targets, "2") == 1
doAssert tree.clicks_at(v, targets, "1") == 0

doAssert take_error() == ""
ew_view_free(v)
echo "page_tree ok"
