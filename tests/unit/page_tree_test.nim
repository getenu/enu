## Declarative pages against a real Blitz document: only the differences are
## applied, they're logged as edits, keyed elements move instead of being
## rebuilt, and clicks are matched by path.

import std/strutils
import ../../src/pages/[renderer, page_tree]

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

# Comparing descriptions needs no document (how a parked page stays parked).
doAssert same_kids(parse_tree(counter(2)), parse_tree(counter(2)))
doAssert not same_kids(parse_tree(counter(2)), parse_tree(counter(3)))

# One description shown in two documents: each keeps its own node ids.
let v2 = ew_view_new("<div id=root></div>", 600, 400, 1.0)
let root2 = ew_query(v2, "#root")
var tree2: PageTree
let shared = parse_tree(counter(5))
discard tree.render(v, root, shared)
discard tree2.render(v2, root2, shared)
discard tree.render(v, root, parse_tree(counter(6)))
discard tree2.render(v2, root2, parse_tree(counter(6)))
doAssert take_error() == ""
doAssert $ew_get_text(v2, root2) == "CounterCount: 6Add one"

# Another player's copy: a page changed by DOM calls is described from its
# document, rebuilt elsewhere from that, and a click there finds its way back
# to the element by path.
let author = ew_view_new(
  "<style id=enu-style>p { color: red }</style><style>b { color: blue }</style>" &
    "<h2>Shop</h2><ul><li>apple</li><li id=pear>pear</li></ul>",
  600, 400, 1.0,
)
let described = parse_tree($ew_describe(author, NO_NODE, true))
var author_tree: PageTree
author_tree.adopt(described)
let sent = described.to_tokens
doAssert "enu-style" notin sent, "Enu's own stylesheet isn't part of the page"
doAssert "b { color: blue }" in sent, "the page's own stylesheets are"
doAssert "I" & FIELD_SEP notin sent, "node ids stay home"

let copy = ew_view_new("<div id=root></div>", 600, 400, 1.0)
let copy_root = ew_query(copy, "#root")
var copy_tree: PageTree
discard copy_tree.render(copy, copy_root, parse_tree(sent))
doAssert $ew_get_text(copy, copy_root) == "b { color: blue }Shopapplepear"
let clicked = click_target(copy, "#pear")
let path = copy_tree.path_of(copy, NodeId(clicked[0]))
doAssert path == "2/#pear", path
let target = author_tree.node_at(path)
doAssert $ew_get_text(author, target) == "pear"

# Relative URLs resolve inside Enu (and load nothing) instead of breaking
# the page.
let images = ew_view_new("<img src=icons/x.png><a href=other>x</a>", 100, 100, 1.0)
discard ew_content_height(images)
doAssert take_error() == ""
ew_view_free(images)

# The hand cursor: over links (and anything styled `cursor: pointer`), not
# over buttons or text, as in a browser.
let cursors = ew_view_new(
  "<p><a id=go href=x>go</a> plain text</p><button id=b>B</button>" &
    "<div id=c style='cursor: pointer'>C</div>",
  600, 400, 1.0,
)
proc hover(v: ViewPtr, selector: string): bool =
  var r: array[4, float32]
  ew_rect(v, ew_query(v, selector.cstring), r.addr)
  var changed = false
  discard ew_pointer(v, POINTER_MOVE, r[0] + r[2] / 2, r[1] + r[3] / 2, changed.addr)
  ew_view_pointing(v)
doAssert cursors.hover("#go"), "a link"
doAssert not cursors.hover("#b"), "a button"
doAssert cursors.hover("#c"), "cursor: pointer"
doAssert not cursors.hover("p"), "text"
ew_view_free(cursors)

# HTML and markdown turn into descriptions without a page.
let md = parse_tree($ew_describe_html("<h1>Hi</h1><p>there <em>you</em></p>"))
doAssert md.len == 2 and md[0].tag == "h1" and md[1].kids[1].tag == "em"

doAssert take_error() == ""
ew_view_free(author)
ew_view_free(copy)
ew_view_free(v2)
ew_view_free(v)
echo "page_tree ok"
