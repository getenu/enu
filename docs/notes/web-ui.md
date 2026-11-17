# Web UI

Status: prototypes 1–9 done as a spike (see Results). Nothing ships yet;
web signs and script pages are behind `-d:enu_web`.

## Goal

Enu's UI, from toolbars to in-world signs, is built with web technologies
instead of Godot's UI system. Players can use the same technologies to make
in-game apps, up to and including 2D games and fast 3D with shaders. Apps
written for Enu also run as normal web apps in a normal browser. Arbitrary
websites loading inside Enu is a non-goal.

## Decisions so far

- **One engine on every platform, and not WebKit.** iOS must work (after the
  Godot 4 move). macOS uses the same path iOS will, so iOS problems show up
  early, on the desktop.
- **No network access** for in-game pages to start. Adding it later is a
  separate, deliberate design.
- **Nim only to start, no JS engine.** UI and apps are written in Nim. Inside
  Enu they run natively (Enu's own UI) or in the Nim VM (player scripts). In a
  normal browser they are compiled with Nim's JS backend. A JS engine
  (QuickJS, interpreter only) stays an option for later.
  With no network and no JS engine this is an HTML renderer driven by Enu's
  scripting, not a web browser, which keeps us clear of App Store rule 2.5.6.
- **Binary size matters** more than build complexity. Rust/cargo in the build
  is fine, through `nim prereqs` like everything else.
- **Pages render to flat planes.** Deeper 3D integration goes through a
  message bridge to Enu's script world (an `enu` module that is stubbed in a
  normal browser), not by putting page content into the Godot scene.
- **Canvas 2D and WebGPU are required and must be fast.** These can be our
  own limited versions, but they follow the real APIs. WebGPU rather than
  WebGL: it's the newer API, and wgpu implements it directly.
- **Scratch-style blocks are our own, written in Nim.** Feeling familiar to
  Scratch users is an explicit goal. We reproduce the shared visual
  conventions (hat/stack/C/reporter/boolean shapes, category colors, palette,
  snap-on-drag), not Scratch's art or name.
- **Signs come first,** before toolbars and other screen UI.

## Engine

**Blitz** (DioxusLabs) is the lead candidate: Rust, MIT/Apache, Firefox's CSS
engine (Stylo), Taffy layout (flex, grid, block, inline, tables), Vello
drawing. It has no JS, which suits the Nim-only plan. In 2024 a stripped
macOS build was ~12MB, against ~98MB for Servo. It reportedly builds for
`aarch64-apple-ios`. It is experimental and its API is still changing.

The fallback is **Servo** (full engine with SpiderMonkey JS, ~98MB). It has
no official iOS support, and its SVG DOM was still stubs as of mid-2026.

Ruled out:

| Option | Why not |
|---|---|
| System web views | No usable path to draw into a texture (WKWebView only draws while on screen) |
| CEF | No iOS/Android; 150MB+ |
| Cobalt | Since Cobalt 27 it's a full Chromium fork; the old lightweight engine is legacy |
| Ladybird | Pre-alpha, no embedding API, runs as several processes |
| Ultralight | License |
| Chawan | Lays out for terminal cells, not pixels (its Chame parser and Monoucha QuickJS glue could be reused) |
| Ferus | Toy engine |
| litehtml | Only basic flexbox, no grid; emergency fallback |
| RmlUi, Sciter | Not standard HTML, or proprietary |

## Architecture

```
Nim UI framework (one API)
├── native backend ── Enu's own UI (toolbars, block editor), compiled in
├── VM backend ────── player scripts, through the host bridge
└── JS backend ────── a normal browser, through Nim's JS backend

Web engine (Rust library, C interface, knows nothing about Godot)
  create view / resize / input / pump / frame
  DOM: CPU drawing (vello_cpu) → RGBA buffer
  <canvas>: reserves a rectangle; content drawn on the GPU (below)

Godot adapter (thin; rewritten for Godot 4)
  frame → texture, input forwarding, views on signs / screen
```

The C interface and the framework carry over unchanged from Godot 3 to 4.
Only the adapter is rewritten, and it should be a few hundred lines.

### Threads

A page lives on the thread of the code that owns it. Blitz documents can be
created on any thread but can't move between threads afterwards (they aren't
`Send`); the recorded drawing commands (`anyrender::Scene`) can.

```
worker thread                       render thread            main thread
VM ⇄ Blitz page (real DOM)  ──recording──▶ rasterize ──frame──▶ upload texture
     style, layout, hit testing                                  aim ray → u, v
     ◀──────────────────────── pointer events (u, v) ───────────────────
```

- Scripts get direct, synchronous DOM access, layout reads included.
- Pointer events go to the worker as positions on the page. The worker hit
  tests, updates `:hover`/`:active`, and queues clicks for the script.
- The main thread only uploads finished frames and forwards the aim ray.
- Enu's own UI keeps its pages on the main thread.
- The hand-off lives in Rust (`tools/web_spike/src/hub.rs`): pages are named
  by key (Enu uses the sign id). It holds the newest frame per key with a
  version, so a recreated sign node can ask again, and queues pointer events.
- Multiplayer: a remote copy of a page would be kept in sync by replaying an
  ordered log of DOM edits from the owner. Not designed yet.

### Canvas 2D and WebGPU

Page layout changes rarely, so it is drawn on the CPU. Canvas content changes
every frame and is drawn on the GPU into its own texture, which Enu composites
over the page.

- **Godot 4:** wgpu, sharing its textures into Godot through
  `RenderingDevice.texture_create_from_extension` (Vulkan or Metal handles).
  - WebGPU maps almost directly onto wgpu, and shaders are WGSL.
  - Canvas 2D uses GPU Vello.
  - Open question: wgpu and Godot sharing one device, versus two devices
    sharing textures.
- **Godot 3:** CPU canvas only, for prototyping. Don't build GPU canvas
  twice.
- **No JIT, so the cost of each script call is the real limit.** Favour
  retained objects (Path2D, buffers, bind groups), batched calls, and a few
  Enu fast paths (e.g. sprite batches). WebGPU is already shaped this way.
  For heavy canvas work, write against the native backend rather than the VM
  where possible.

## Blocks

- **Text is the source of truth.** The `.nim` script stays canonical; blocks
  are a view of it. Block positions and other layout go in side metadata,
  never in the script.
- **Round-trip through the AST.** Parse with the Nim compiler's parser (it's
  already in-process for the VM). Constructs in the happy-path subset become
  real blocks. Anything else becomes a "code" block that holds raw text, so
  any script can be opened as blocks. Blocks print back to text using the
  project's formatting.
- **The happy-path subset** is defined by the code in shipped levels:
  - commands with optional arguments (`forward 10`, `turn right`,
    `lean back, 90`)
  - assignments to properties (`color = brown`, `scale = 0.25`)
  - `let`/`var`
  - `if`/`elif`/`else`, `while`, `n.times(i):`
  - ranges as values (`0 .. 360`), `cycle(...)`
  - simple `proc`s with parameters, and calls to them
  - Enu's state-machine syntax

  Shipped levels should round-trip without falling back to code blocks. A
  test that loads every script under `share/` and checks that
  text → blocks → text comes back identical keeps that true.
- **Comments and blank lines** are the usual round-trip trap. They must
  survive, either attached to blocks or as comment blocks.
- **Where blocks appear:** mainly a 2D panel (the editor). The code
  billboards above players' heads show blocks too. They're always-on-top
  billboards, so they're effectively 2D panels drawn to a texture. In-world
  interactive block panels are a stress test, not a user-facing feature.
- **Drawing:** the block editor draws on canvas 2D (precedent: Snap! draws
  its whole UI on one canvas). It's Enu UI, so it runs native, not in the VM.

## Command loops, events and pages

Settled in discussion (2026-11-17). Long-term direction, not built yet,
except where noted.

- **One command loop per thing.** A thing has one state machine, which may
  be written in pieces and may nest, but there are no peer state machines.
  Two independent behaviors are two things. `loop` is expected to become
  bare `on:`, with `on <event>:` forms alongside it.
- **The loop body is rules.** It runs an undetermined number of times: every
  0.5s, when something interesting happens (a collision, a click), and once
  per combination of query results. It should mostly decide which state the
  thing is in. Commands run as states' actions.
- **Queries hand out everything that happened in a tick, one result per
  pass** (`if Player.added as p:`). Results last one tick. Nested queries
  run once per combination (each player with each build); sibling queries
  are independent, since a rule can only see the results it's nested in.
  The current code doesn't do this yet: see #152.
- **Clicks are a query.** `if button.clicked as click:` (built), and `on
  click(el):` as sugar for it. A click wakes the thing so it's handled in the
  same tick, even mid-command. A `->` inside one only fires if the thing is
  idle in that state, the same as any other query.
- **Data changes on click are fine** (`inc count`), as long as each result is
  handled once: that's why siblings must not be multiplied together.
- **Pages are declarative and live in the loop body.** `page board:`
  describes the whole page on each pass; the host compares it with the last
  description and applies only the differences. `on click:` inside an
  element is the click query for that element. A page described inside a
  state only exists in that state. The differences are also the edit log
  other players would replay (syncing not designed yet).
- **Open:** what a transition does to the rest of a tick's results (proposed:
  the first transition wins, and the remaining results are still processed);
  whether `on X:` loops can run commands (proposed: no, which also makes them
  possible in native Enu, where nothing can pause mid-pass).

## Prototypes

Each one answers one question. Stop and reassess if one fails.

1. **Blitz offscreen behind a C interface.** A Nim test program loads HTML
   and writes a PNG. Measure: added size (macOS and an iOS build), time to
   draw a sign-sized page, memory per page.
2. **Nim VM driving the page.** A script builds and updates a page through
   the host bridge, including clicks.
3. **The same UI code compiled to JS** in a regular browser. The start of the
   framework.
4. **Canvas plus blocks.** A `<canvas>` with a Nim 2D API, drawing a few
   draggable, snapping blocks. Tests text quality, antialiasing and hit
   testing.
5. **Block round-trip.** Parse a shipped level script, convert it to a block
   tree, print it back, and diff. Doesn't depend on the renderer, so it can
   run in parallel with 1–4.
6. **A web sign in Godot 3.** Texture on the sign's quad; markdown signs
   become markdown converted to HTML, so the sign API doesn't change. Static
   signs draw once and free their view.
7. **Pages on the worker thread.** The page lives next to the script for
   direct DOM access; a render thread rasterizes; the main thread uploads and
   forwards the pointer. Completes 2 (clicks).
8. **Panics as errors.** A renderer bug becomes a script error, not a crash.
9. **Declarative pages.** `page board:` in the command loop, with
   differences applied on the host and logged as edits.

After Godot 4: port the adapter, GPU canvas and WebGPU through wgpu, then the
iOS build.

## Results (spike, 2026-11-16)

Code: `tools/web_spike/` (Rust C interface, Nim bindings, `web_ui` module),
`tools/blocks_spike/` (blocks), `src/nodes/sign_web.nim` (signs, behind
`-d:enu_web`). Blitz 0.3.0-beta.4, CPU drawing with `vello_cpu`. Measured on
an Apple Silicon Mac.

**1. Offscreen rendering works and is fast.**

| | |
|---|---|
| First page created (includes system font discovery) | 37–265 ms |
| Each later page created | ~15 ms |
| Draw a 1200×1200 sign page (first / again / after a text change) | 2–3 / 0.7 / 1.0 ms |
| Memory | ~30 MB for the first page (fonts), ~3 MB per extra 600×600 page |
| Added to Enu's release dylib, stripped and dead-stripped | **+8.6 MB** (10.8 → 19.4 MB) |
| The library alone, built for size (`opt-level = "z"`) | 5.3 MB, but drawing is ~6× slower |

- The best trade-off is probably `opt-level = "z"` for most crates, with
  `vello_cpu` kept at full optimization. Not tried yet.
- iOS: the renderer builds and links for `aarch64-apple-ios` (as a
  stripped dylib: 9.06MB, about the same as macOS). It hasn't run on a
  device or the simulator yet.

**2/6. Real Enu signs render through Blitz.** With `-d:enu_web` every
markdown sign is converted with the markdown dependency Enu already uses, laid
out by Blitz, and uploaded as an `ImageTexture` in place of the viewport and
MarkdownLabel. Tutorial signs, the animated welcome ticker, and HTML set from
a script (flexbox, gradients, rounded corners) all render in-world. Found:

- Signs use a lit material with forced sRGB, so scene lighting shifts page
  colors. Current signs have the same problem. UI-quality color needs an
  unshaded sign material.
- nim-markdown doesn't do task lists (`- [ ]`). MarkdownLabel did, so a few
  tutorial signs read worse. Either add it or handle it in our converter.
- Scripts can only replace a sign's whole message so far. Not built yet:
  live DOM handles in the VM, and click forwarding from the 3D sign into the
  page and back to the script.

**3. One app, two backends.** `counter_app.nim` runs natively through Blitz
(clicks by position, bubbling to handlers) and compiles to JS (79 KB) with
identical results. The JS version was smoke-tested in JavaScriptCore with a
stub DOM, not yet in a real browser.

**4. Canvas works through a Blitz custom widget.** This answers the earlier
open question: Blitz's custom widget API (`set_custom_widget` + `paint` into
an anyrender `Scene`) is exactly the hook needed. The spike records
CanvasRenderingContext2D-style commands (paths, fill, stroke, fillText via
parley, measureText). On Godot 4 the same widget can register a GPU texture as
a resource instead of drawing on the CPU. A whole script drawn as blocks
(1100×1474) lays out, draws and renders in ~8 ms; redrawing after a drag
takes ~3 ms.

**5. Blocks round-trip.** Text is parsed with Enu's nph fork (it keeps
comments), turned into blocks, printed back as plain text and formatted by
nph.

- All 129 hand-written scripts under `share/worlds` come back **identical**.
- **92.9%** of statements become real blocks; the rest are code blocks.
- The remaining code blocks are mostly:
  - imports (100)
  - grouped `let`/`var`/`const` sections
  - templates
  - transitions with a body (`a ==> b do:`)
  - bare boolean expressions
  - `case`
- Things learned:
  - Blank lines must be kept. They also map nicely to separate block stacks.
  - Trailing and header comments attach to blocks.
  - nph's renderer reads atom text from file 0 of its config, so every parse
    needs a fresh config, and a tree can't be stitched together from several
    parses. Printing blocks as text and letting nph format it avoids both
    problems, and it's what an editor would do anyway.
- `blocks_demo.nim` draws shipped scripts as blocks and performs a drag: a
  pointer hit test, a snap to the nearest bottom edge, and a move in the
  tree. The text diff shows the statement moving with its comment.

**7. Pages on the worker thread, with clicks.** A script turns a sign into
a page and changes it directly:

```nim
let board = say("page", width = 12, height = 0, size = 0.7)
board.html = "<h2>Bolt's Counting Machine</h2><p>Count: <b id=count>0</b></p>" &
  "<button id=add>Add one</button><ul id=log></ul>"
var count = 0
loop:
  if board["#add"].clicked as click:
    inc count
    board["#count"].text = $count
    board["#log"].add board.element("li", \"pressed it, now {count}")
```

- API (`share/vmlib/enu/pages.nim`): `sign.html=`, `sign[selector]`,
  `sign.element(tag, text)`, `add`, `remove`, `text`/`text=`, `html=`,
  attributes with `[]`/`[]=`, `parent`, `rect` (layout, always current), and
  `clicked`. Element handles are Blitz node ids.
- Host side: `src/controllers/script_controllers/web_pages.nim`, bridged in
  `host_bridge.nim` and pumped from the worker loop (pointer events before
  scripts run, changed pages recorded after).
- Clicks are a query, like `Player.hit`. `clicked(el)` counts the clicks
  this tick on the element or anything inside it; `as` hands them out one
  per pass, and the loop runs until they've all been handled. The host keeps
  a page's clicks for the tick they arrive in, so evaluating the query
  doesn't consume anything. A click wakes the owner, as a bump does, so its
  loop sees the click the same tick. Query results are stored as `RootRef`
  now (they were `Thing`), so a query can hand out things that aren't Things.
- The first version used callbacks (`on_click`) run from a hook in `wait`.
  That's the model Enu avoids, and it only ran handlers after a command
  finished. Replaced by the query.
- Until #152 is fixed, a click handled in a pass during a long command can
  be seen again on the next wake pass of that command (the stored result
  isn't popped there). Things that are only a UI don't hit this.
- Measured in game (welcome level, page 1200 px wide):
  - Worker, per changed frame, style + layout + recording: 0.12–0.5 ms,
    including a 14,600 px tall page.
  - Worker, pointer events: 0.01–0.2 ms per batch.
  - Script DOM calls: edit + layout read 0.08 ms, text read 0.02 ms, 200
    `li` appended 8.8 ms (~0.04 ms each through the bridge).
  - Render thread: 0.5–1.8 ms per frame.
  - Main thread upload: ~6 ms per changed frame (1200×573) on the tools
    build of Godot 3. It was 54 ms until the copy into `PoolByteArray` used
    one write lock instead of `mitems`. Reusing the texture or dropping
    mipmaps didn't change it. On Godot 4 the frame can go straight to a
    `RenderingDevice` texture, or a shared wgpu texture.
- Tested by posting pointer events from a script (`page_post_pointer`) into
  the same queue the main thread uses: three clicks → count 3, three list
  items, hover style on the button under the pointer. The real aim path
  (ray → u, v in `aim_target.nim` and `SignNode.page_pointer`) is written
  but hasn't been tried with a mouse.
- Found a Blitz bug: `remove_and_drop_all_children` (and so
  `set_inner_html` with empty HTML) doesn't mark the parent's layout
  damaged, and the next layout panics on a stale node ("invalid SlotMap key
  used"). Worked around by removing children one at a time. Worth reporting
  upstream.
- Panics used to abort Enu. See 8.
- Pages are capped at 4096 px tall until they scroll.

**8. Panics stop at the C interface.** Every exported function runs inside
`guard` (`tools/web_spike/src/guard.rs`), which catches panics and stores the
message for `ew_take_error`.

- In a script call, the error becomes a script error ("The page had a
  problem: ..."). In the worker loop and on the main thread it's logged.
- A panic may leave a page half-changed, so that page refuses further calls
  until its HTML is set again. Caller mistakes found before anything changes
  (a node id that doesn't exist) are reported without breaking the page.
- An element that wasn't found gives a script error naming its selector.
- The render thread skips a frame that panics instead of dying.
- Unwinding costs about 1.7MB: the stripped library is 10.9MB (9.0–9.2MB
  with `panic = "abort"`).
- Tested natively (`nim/guard_test.nim`) and in game: setting the text of a
  missing element used to be a Blitz panic; now it's a script error.

**9. Declarative pages.** `page board:` in a command loop describes the
whole page on each pass:

```nim
var count = 0
loop:
  page board:
    h2 "Bolt's Counting Machine"
    p:
      text "Count: "
      b $count
    button(id = "add"):
      text "Add one"
      on click:
        inc count
    if count > 0:
      button(id = "reset"):
        text "Start over"
        on click:
          count = 0
    ul:
      for i in 1 .. count:
        li \"pressed it, now {i}"
```

- Script side (`share/vmlib/enu/pages.nim`): a macro turns HTML tags into
  builder calls. `h2 "text"`, `p:` for children, `pane(class = "row"):` for
  attributes, `text` for plain text, `on click:` inside an element, and
  ordinary `if`/`for`/`case` around them. The description goes to the host
  as one string per pass.
- `pane` is HTML's `div`, which can't be a name in Nim (it's a keyword). The
  meaningful block tags are all there too (`header`, `footer`, `nav`,
  `section`, `article`, `aside`, `main`, ...). Teach "use the tag that says
  what it is; if it's just for layout, use a `pane`".
- `{.piece.}` on a proc lets it describe part of a page, for reuse. It has to
  be called inside a `page` block.
- Host side (`tools/web_spike/nim/page_tree.nim`, no Enu dependencies):
  compares it with the last description and applies only the differences:
  text and attribute changes, adds, removes, moves. Each one is logged as an
  edit (`text 2/1/0 3`, `add 4/#bot_rat li`, `move 0/#crab`), readable from a
  script with `board.page_edits()`. That's the stream other players would
  replay.
- Identity: an element's `id` is its key, and elements made in a loop over
  things (`for bot in Bot.all:`) take the thing's id automatically. Keyed
  elements are matched by key wherever they move; others by position. As in
  Karax, the unchanged start and end of each child list are skipped first,
  so one insert or removal is one edit even without keys. Out-of-order keyed
  elements are moved, as few as possible (longest increasing run).
- Paths name elements for clicks and edits: a key as `#key`, else the index
  among siblings (`4/#bot_rat/1`). The script computes the same paths while
  it describes the page, so `on click:` finds the element the player clicked
  even if the list moved since.
- If an `on click` body ran, the page is described again without running
  handlers, so the change shows on the same pass.
- Tested natively (`nim/page_tree_test.nim`: keyed insert, move, a click
  following its item after a shift, unkeyed insert at the top) and in game:
  the counter, a `{.piece.}`, a `pane` row, and a list of every bot with a
  "wave" button each, keyed by bot id. Worker cost per changed pass
  0.25–1 ms.
- Inherits the query bugs in #152 (a click handled in a pass during a long
  command can repeat on the next wake pass).

## Open questions

- Blitz text input, focus and IME. `:hover`/`:active` and clicks work
  (prototype 7); keyboard input isn't forwarded yet.
- Try the aim-ray click path with a real mouse, including billboard signs.
- Query semantics (#152): results last one tick, combinations follow
  nesting, the first transition in a tick wins.
- Main-thread upload cost on Godot 3 (~6 ms per changed frame).
- How DOM edits sync to other players (to discuss).
- Is the Nim VM fast enough for interactive UI driven by player scripts, or
  do player apps need a faster path (QuickJS, or Nim compiled to Wasm under
  an interpreter)?
- The cargo build is a separate `nim build_web` task. Before anything ships
  it belongs in `nim prereqs` and `nim dist`.
- Multiplayer for in-game apps: the owner's page is the source of truth and
  other players replay its DOM edit log (see Threads). Not designed yet; it
  only needs to be possible.
