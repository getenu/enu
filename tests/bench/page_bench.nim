## How pages scale: an inventory-like page of `ITEMS` keyed rows, each a few
## nested elements, through every step a change takes on its way to another
## player's screen. Run with `nim c -r -d:release tests/bench/page_bench`.

import std/[monotimes, times, strutils, strformat, algorithm]
import ../../src/pages/[renderer, page_tree]

const
  ITEMS = 500
  RUNS = 20

proc e(tag: string): string = "E" & FIELD_SEP & tag & TOKEN_SEP
proc k(key: string): string = "K" & FIELD_SEP & key & TOKEN_SEP
proc a(name, v: string): string = "A" & FIELD_SEP & name & FIELD_SEP & v & TOKEN_SEP
proc t(text: string): string = "T" & FIELD_SEP & text & TOKEN_SEP
const c = "C" & TOKEN_SEP

proc inventory(order: seq[int], counts: seq[int]): string =
  result = e("h2") & t("Inventory") & c & e("ul")
  for i in order:
    result &= e("li") & k("item" & $i) & a("class", "slot")
    result &= e("img") & a("src", "icons/" & $i & ".png") & c
    result &= e("span") & a("class", "name") & t("Item number " & $i) & c
    result &= e("span") & a("class", "count") & t($counts[i]) & c
    result &= e("button") & t("Use") & c & e("button") & t("Drop") & c
    result &= c
  result &= c

proc ms(start: MonoTime): float =
  (get_mono_time() - start).in_microseconds.float / 1000

proc median(xs: seq[float]): float =
  xs.sorted[xs.len div 2]

var order: seq[int]
var counts: seq[int]
for i in 0 ..< ITEMS:
  order.add i
  counts.add 1

let v = ew_view_new("<div id=root></div>", 1200, 1200, 1.0)
let root = ew_query(v, "#root")
var tree: PageTree

var first = inventory(order, counts)
var start = get_mono_time()
discard tree.render(v, root, parse_tree(first))
let initial = ms(start)

var parse, same, one, moved, layout, describe, tokens: seq[float]
for run in 0 ..< RUNS:
  let unchanged = inventory(order, counts)
  start = get_mono_time()
  let kids = parse_tree(unchanged)
  parse.add ms(start)
  start = get_mono_time()
  doAssert same_kids(tree.root.kids, kids)
  same.add ms(start)

  inc counts[run * 7 mod ITEMS]
  start = get_mono_time()
  discard tree.render(v, root, parse_tree(inventory(order, counts)))
  one.add ms(start)

  order.insert(order.pop, run mod ITEMS)
  start = get_mono_time()
  discard tree.render(v, root, parse_tree(inventory(order, counts)))
  moved.add ms(start)

  start = get_mono_time()
  ew_resize(v, 1200, 1200)
  discard ew_content_height(v)
  layout.add ms(start)

  start = get_mono_time()
  let described = parse_tree($ew_describe(v, root, true))
  describe.add ms(start)
  start = get_mono_time()
  discard described.to_tokens
  tokens.add ms(start)

doAssert take_error() == ""
echo &"{ITEMS} items, {first.len div 1024} KB described"
echo &"first render:            {initial:.2f} ms"
echo &"parse a description:     {parse.median:.2f} ms"
echo &"compare, unchanged:      {same.median:.2f} ms"
echo &"one count changed:       {one.median:.2f} ms (parse + diff + apply)"
echo &"one item moved:          {moved.median:.2f} ms (parse + diff + apply)"
echo &"layout after a change:   {layout.median:.2f} ms"
echo &"describe from the DOM:   {describe.median:.2f} ms (walk + parse)"
echo &"back to tokens:          {tokens.median:.2f} ms"
ew_view_free(v)
