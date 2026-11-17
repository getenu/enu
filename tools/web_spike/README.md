# Web UI spike

Prototypes for rendering Enu's UI with web technologies. See
`docs/notes/web-ui.md` for the plan and results.

- `src/` — a C interface over [Blitz](https://github.com/DioxusLabs/blitz):
  render HTML to an RGBA buffer, change the DOM, hit test, and a `<canvas>`
  custom widget that replays 2D drawing commands. Knows nothing about Godot.
- `src/guard.rs` — panics stop at the C interface and become errors.
- `src/hub.rs` — moving pages between threads: the render thread, finished
  frames by key, and pointer events going back.
- `nim/enu_web.nim` — Nim bindings for it.
- `nim/sign_page.nim` — how sign text becomes a page (shared by the main
  thread and the worker).
- `nim/page_tree.nim` — declarative pages: compare a description with the
  last one, apply the differences, log them as edits.
- `nim/guard_test.nim`, `nim/page_tree_test.nim` — native tests (run from
  the repo root: `nim c -r -d:release tools/web_spike/nim/<test>.nim`).
- `nim/web_ui.nim` — one small UI API with two backends: native (Blitz) and
  JS (`nim js`, the browser DOM and canvas).
- `nim/spike1.nim` — render a sign page to PNG and measure speed and memory.
- `nim/counter_app.nim` + `spike3.nim` — one app, run natively (clicks by
  position) and compiled to JS (`web/index.html`).
- `../blocks_spike/` — blocks ↔ Nim round trip, and blocks drawn on the canvas.
- Script pages (prototype 7) live in Enu itself:
  `share/vmlib/enu/pages.nim` (script API),
  `src/controllers/script_controllers/web_pages.nim` (worker side),
  `src/nodes/sign_node.nim` and `aim_target.nim` (main thread).

```sh
nim build_web                      # cargo build --release
nim c -r -d:release tools/web_spike/nim/spike1.nim <out_dir>
nim c -r -d:release tools/web_spike/nim/spike3.nim <out_dir>
nim js -o:tools/web_spike/web/counter_app.js tools/web_spike/nim/counter_app.nim
nim build -d:enu_web               # Enu with every sign rendered by Blitz

# blocks (run from the repo root so nim.cfg finds nph)
nim c -r -d:release -d:nph tools/blocks_spike/roundtrip.nim share/worlds
nim c -r -d:release -d:nph --path:tools/web_spike/nim \
  tools/blocks_spike/blocks_demo.nim <script.nim> <out_dir>
```
