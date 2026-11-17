## Prototype 1: render HTML offscreen through the C interface and measure it.

import std/[monotimes, times, strformat, os, strutils]
import enu_web

proc max_rss_mb(): float =
  var usage: tuple[ru_utime, ru_stime: array[2, clong], ru_maxrss: clong, rest: array[13, clong]]
  proc getrusage(who: cint, usage: pointer): cint {.importc, header: "<sys/resource.h>".}
  discard getrusage(0, usage.addr)
  when defined(macosx):
    usage.ru_maxrss.float / 1024 / 1024
  else:
    usage.ru_maxrss.float / 1024

template timed(label: string, body: untyped) =
  let start = get_mono_time()
  body
  let ms = (get_mono_time() - start).in_microseconds.float / 1000
  echo label, ": ", ms.format_float(ff_decimal, 2), " ms"

const sign_html = """
<!doctype html>
<style>
  body { margin: 0; font-family: sans-serif; background: #f6efe0; color: #2b2118; }
  .sign { padding: 32px 40px; border: 12px solid #8a5a2b; }
  h1 { margin: 0 0 12px; font-size: 64px; }
  p { font-size: 34px; line-height: 1.35; margin: 0 0 16px; }
  code { background: #2b2118; color: #f6efe0; padding: 2px 8px; border-radius: 6px; }
  .row { display: flex; gap: 16px; }
  .chip { flex: 1; background: #4a7bd0; color: white; border-radius: 18px;
          padding: 16px; text-align: center; font-size: 30px; }
  .chip:nth-child(2) { background: #3f9b5b; }
  .chip:nth-child(3) { background: #d0644a; }
  ul { font-size: 30px; margin: 0 0 16px; }
</style>
<div class="sign">
  <h1>Welcome to the Workshop!</h1>
  <p>Hello friend! I am <b>Bolt</b>, and I have built this sign <i>entirely
  myself</i>, mostly. Type <code>forward 10</code> to move ten whole blocks,
  which is more than nine.</p>
  <ul><li>Build a tower</li><li>Paint it blue</li><li>Wonder why it is blue</li></ul>
  <div class="row">
    <div class="chip" id="build">Build</div>
    <div class="chip" id="play">Play</div>
    <div class="chip" id="code">Code</div>
  </div>
  <p id="status">Nothing pressed yet.</p>
</div>
"""

let out_dir = if param_count() > 0: param_str(1) else: get_temp_dir()
let (w, h) = (1200'u32, 1200'u32)

echo &"rss at start: {max_rss_mb():.1f} MB"
var v: ViewPtr
timed "first view (incl. font discovery)":
  v = ew_view_new(sign_html, w, h, 1.0)
timed "first render 1200x1200":
  discard ew_render(v)
for i in 1 .. 3:
  timed &"re-render {i} (no changes)":
    discard ew_render(v)
echo &"content height: {ew_content_height(v):.0f} px"
doAssert ew_write_png(v, cstring(out_dir / "spike1_sign.png"))

let status = ew_query(v, "#status")
doAssert status != NO_NODE
timed "text change + render":
  ew_set_text(v, status, "Text changed from Nim.")
  discard ew_render(v)

# Hit test the middle of the "Play" chip by finding it from a point scan.
var hit = NO_NODE
for y in countup(0, ew_content_height(v).int, 8):
  let n = ew_element_at(v, 600, y.float32)
  if v.get_attribute(n, "id") == "play":
    hit = n
    break
doAssert hit != NO_NODE, "hit test found #play"
ew_set_text(v, status, "You pressed Play. Bolt is very proud of you.")
discard ew_render(v)
doAssert ew_write_png(v, cstring(out_dir / "spike1_clicked.png"))
echo &"rss after one view: {max_rss_mb():.1f} MB"

# Many signs: memory per view.
var views: seq[ViewPtr]
timed "create + render 20 more views":
  for i in 0 ..< 20:
    let x = ew_view_new(cstring(sign_html.replace("Bolt", "Bolt " & $i)), 600, 600, 0.5)
    discard ew_render(x)
    views.add x
echo &"rss after 21 views: {max_rss_mb():.1f} MB"
for x in views:
  ew_view_free(x)
ew_view_free(v)
echo "pngs in ", out_dir
