## Prototype 3, native half: run counter_app through Blitz and click its
## buttons by position, the way input forwarded from Godot would.

import std/[os, strformat]
import web_ui, counter_app, enu_web

let out_dir = if param_count() > 0: param_str(1) else: get_temp_dir()
let ui = new_ui(app_html, 900, 700)
start(ui)
discard ui.render()

proc center_of(selector: string): (float, float) =
  ## The spike has no layout query yet, so find an element by scanning.
  let target = ui.query(selector)
  for y in countup(0, ui.height, 4):
    for x in countup(0, ui.width, 8):
      let n = ew_element_at(ui.view, x.float32, y.float32)
      if n == target.id:
        return (x.float + 20, y.float + 20)
  doAssert false, &"{selector} not found"

let plus = center_of("#plus")
let minus = center_of("#minus")
for _ in 1 .. 3:
  doAssert ui.click(plus[0], plus[1])
doAssert ui.click(minus[0], minus[1])
doAssert not ui.click(5, 5), "background has no handler"
ui.save_png(out_dir / "spike3_counter.png")
echo "count after +3 -1 rendered to ", out_dir / "spike3_counter.png"
ui.close()
