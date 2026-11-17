## Prototypes 4 + 5 together: a shipped script, turned into blocks, drawn on
## a canvas inside a Blitz page, then edited by "dragging" a block with
## pointer coordinates, and turned back into Nim.
##
##   nim c -r -d:nph --path:tools/web_spike/nim tools/blocks_spike/blocks_demo.nim [script] [out_dir]

import std/[os, strformat, monotimes, times, strutils]
import blocks, block_view, web_ui

let
  script =
    if param_count() > 0: param_str(1)
    else: "share/worlds/tutorial/.claude/examples/fractal_tree.nim"
  out_dir = if param_count() > 1: param_str(2) else: get_temp_dir()
  source = read_file(script)

var stats: Stats
var script_blocks = to_blocks(parse(source), stats)
let before = to_source(script_blocks)

const WIDTH = 1100
let height = int(View().script_height(script_blocks)) + 60
let ui = new_ui(
  &"""<body style="margin:0;background:#f4f5f7">
  <canvas id="c" style="width:{WIDTH}px;height:{height}px"></canvas></body>""",
  WIDTH,
  height,
)
var v = View(c: ui.canvas(ui.query("#c")))

var start = get_mono_time()
discard v.draw_script(script_blocks, 20, 24)
discard ui.render()
echo &"layout + draw + render {WIDTH}x{height}: {(get_mono_time() - start).in_microseconds.float / 1000:.1f} ms, {v.hits.len} blocks"
ui.save_png(out_dir / "blocks_before.png")

# Drag the first `sphere` block (the leaf cluster) up to just under the
# first `color = ...` block, the way a pointer would: press on it, release
# near the target's bottom edge, and let it snap.
var grab = -1
for i, h in v.hits:
  if h.b.kind == COMMAND and to_text(h.b.call).starts_with("sphere"):
    grab = i
    break
if grab < 0:
  echo "no sphere block to drag; done"
  quit 0
let picked = v.hits[grab]
doAssert v.hit(picked.x + 6, picked.y + 6) == grab, "pointer finds the block"

var target = -1
for i, h in v.hits:
  if h.b.kind == ASSIGN and to_text(h.b.target) == "color":
    target = i
    break
if target < 0:
  echo "no color block to drop on; done"
  quit 0
let t = v.hits[target]
let drop = v.drop_target(t.x + 3, t.y + t.h + 4)
doAssert drop == target, "drop snaps to the block above"

let moving = picked.list[][picked.index]
picked.list[].delete(picked.index)
var at = t.index + 1
if picked.list == t.list and picked.index < t.index:
  dec at
t.list[].insert(moving, at)

start = get_mono_time()
discard v.draw_script(script_blocks, 20, 24)
discard ui.render()
echo &"redraw after drag: {(get_mono_time() - start).in_microseconds.float / 1000:.1f} ms"
ui.save_png(out_dir / "blocks_after.png")

let after = to_source(script_blocks)
write_file(out_dir / "blocks_before.nim", before)
write_file(out_dir / "blocks_after.nim", after)
echo "text diff after the drag:"
discard exec_shell_cmd(&"diff -u {out_dir / \"blocks_before.nim\"} {out_dir / \"blocks_after.nim\"}")
ui.close()
