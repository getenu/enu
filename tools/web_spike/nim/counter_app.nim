## One app, written once against web_ui. Built natively by spike3.nim and as
## JS by `nim js counter_app.nim`.

import web_ui

const app_html* = """
<style>
  body { margin: 0; font-family: sans-serif; background: #1d2433; color: #eef; }
  .panel { padding: 32px; }
  h1 { margin: 0 0 8px; font-size: 48px; }
  .count { font-size: 120px; font-weight: bold; color: #ffd166; }
  .row { display: flex; gap: 16px; margin: 16px 0; }
  .btn { padding: 16px 32px; border-radius: 16px; font-size: 32px;
         background: #4a7bd0; color: white; }
  .btn.minus { background: #d0644a; }
  ul { font-size: 26px; }
</style>
<div class="panel">
  <h1>Bolt's Counting Machine</h1>
  <div class="count" id="count">0</div>
  <div class="row">
    <div class="btn minus" id="minus">− less</div>
    <div class="btn" id="plus">+ more</div>
  </div>
  <ul id="log"></ul>
</div>
"""

const remarks = [
  "That is a number!", "Even more of a number.", "Numbers go up. I checked.",
  "I counted it twice to be sure. It was different.",
]

proc start*(ui: Ui) =
  var count = 0
  let count_el = ui.query("#count")
  let log = ui.query("#log")

  proc changed(by: int) =
    count += by
    ui.set_text(count_el, $count)
    ui.add(log, ui.text("li", remarks[abs(count) mod remarks.len]))

  ui.on_click(ui.query("#plus"), proc() = changed(1))
  ui.on_click(ui.query("#minus"), proc() = changed(-1))

when defined(js) and is_main_module:
  start(new_ui(app_html))
