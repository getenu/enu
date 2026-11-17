## Declarative pages against a real Blitz document: only the differences are
## applied, they're logged as edits, keyed elements move instead of being
## rebuilt, and clicks are matched by path.

import std/strutils
import enu_web, page_tree

proc e(tag: string): string = "E" & FIELD_SEP & tag & TOKEN_SEP
proc k(key: string): string = "K" & FIELD_SEP & key & TOKEN_SEP
proc a(name, v: string): string = "A" & FIELD_SEP & name & FIELD_SEP & v & TOKEN_SEP
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

proc check(tree: var PageTree, expected: seq[string]) =
  let got = tree.take_edits
  doAssert got == expected, "\n  got:      " & $got & "\n  expected: " & $expected

let v = ew_view_new("<div id=root></div>", 600, 400, 1.0)
let root = ew_query(v, "#root")
var tree: PageTree

doAssert tree.render(v, root, parse_tree(counter(0)))
discard tree.take_edits
doAssert $ew_get_text(v, root) == "CounterCount: 0Add one"
doAssert not tree.render(v, root, parse_tree(counter(0))), "nothing changed"

discard tree.render(v, root, parse_tree(counter(1)))
tree.check @["text 1/1/0 1"]
doAssert $ew_get_text(v, root) == "CounterCount: 1Add one"

discard tree.render(v, root, parse_tree(counter(1, items = 2)))
tree.check @["add 3/1 li", "add 3/0 li"]
discard tree.render(v, root, parse_tree(counter(1, items = 1)))
tree.check @["remove 3/1"]
discard tree.render(v, root, parse_tree(counter(1, items = 1, title = "h3")))
tree.check @["remove 0", "add 0 h3"]
doAssert $ew_get_text(v, root) == "CounterCount: 1Add oneitem 1"

# Attributes: change, then drop.
let base = counter(1, items = 1, title = "h3")
discard tree.render(v, root, parse_tree(base.replace(a("id", "add"), a("id", "add") & a("class", "big"))))
tree.check @["attr #add class=big"]
discard tree.render(v, root, parse_tree(base))
tree.check @["unattr #add class"]

# Clicks are matched to elements by path, including clicks on their text.
proc click_target(v: ViewPtr, selector: string): seq[int] =
  var r: array[4, float32]
  ew_rect(v, ew_query(v, selector.cstring), r.addr)
  let target = ew_element_at(v, r[0] + r[2] / 2, r[1] + r[3] / 2)
  doAssert target != NO_NODE
  @[int(target.uint64)]

let on_add = v.click_target("#add")
doAssert tree.clicks_at(v, on_add, "#add") == 1
doAssert tree.clicks_at(v, on_add, "1") == 0

# A keyed list: an insert at the top adds one element, a swap moves one, and
# a click on an item still finds it after the list shifts.
proc bots(names: seq[string]): string =
  result = e("ul")
  for n in names:
    result &= e("li") & k(n) & t(n) & e("button") & a("class", "go") & t("go") & c & c
  result &= c

discard tree.render(v, root, parse_tree(bots(@["rat", "crab"])))
discard tree.take_edits
let on_crab = v.click_target("#root li:nth-child(2) button")
discard tree.render(v, root, parse_tree(bots(@["gull", "rat", "crab"])))
tree.check @["add 0/#gull li"]
doAssert $ew_get_text(v, root) == "gullgoratgocrabgo"
doAssert tree.clicks_at(v, on_crab, "0/#crab") == 1, "the click follows crab"
doAssert tree.clicks_at(v, on_crab, "0/#rat") == 0
discard tree.render(v, root, parse_tree(bots(@["gull", "crab", "rat"])))
tree.check @["move 0/#crab"]
doAssert $ew_get_text(v, root) == "gullgocrabgoratgo"

# Unkeyed, an insert at the top is still one add: the unchanged end is
# skipped first.
proc items(names: seq[string]): string =
  result = e("ul")
  for n in names:
    result &= e("li") & t(n) & c
  result &= c

discard tree.render(v, root, parse_tree(items(@["b", "c"])))
discard tree.take_edits
discard tree.render(v, root, parse_tree(items(@["a", "b", "c"])))
tree.check @["add 0/0 li"]
doAssert $ew_get_text(v, root) == "abc"

doAssert take_error() == ""
ew_view_free(v)
echo "page_tree ok"
