## Spike (`-d:enu_web`): pages that scripts build on signs. A page lives on
## the worker thread next to the script, so scripts read and change the DOM
## directly, with no frame delay. Each tick the worker feeds pages the pointer
## events the main thread posted, and records any page that changed for the
## render thread (tools/web_spike/src/hub.rs). The main thread only uploads
## finished frames.

import std/[tables, monotimes, times, strformat, algorithm, math]
import core, models/signs
import ../../../tools/web_spike/nim/[enu_web, sign_page]

const MAX_PAGE_HEIGHT = 4096
  ## Pages don't scroll yet. Taller ones are cut off rather than turned into
  ## huge textures.

type
  PageRect* = tuple[x, y, width, height: float]

  Page = ref object
    view: ViewPtr
    sign: Sign
    height: int
    dirty: bool
    clicks: seq[int]

var
  pages {.threadvar.}: Table[string, Page]
  present_times {.threadvar.}: seq[float]
  pump_times {.threadvar.}: seq[float]

proc check() =
  ## Turns a failed call into a script error.
  let error = take_error()
  if error != "":
    raise ValueError.init("The page had a problem: " & error)

proc log_errors(key: string) =
  let error = take_error()
  if error != "":
    error "page error", sign = key, error

proc page(self: Sign): Page =
  result = pages.get_or_default(self.id)
  if result.is_nil:
    raise ValueError.init(
      "This sign isn't a page yet. Set its `html` first."
    )

proc page_set_html*(self: Sign, html: string) =
  defer:
    check()
  let full = sign_html(html, font_px(self.size, self.width))
  var page = pages.get_or_default(self.id)
  if page.is_nil:
    page = Page(
      view: ew_view_new(full.cstring, PAGE_WIDTH, PAGE_WIDTH, 1.0),
      sign: self,
      height: PAGE_WIDTH,
    )
    pages[self.id] = page
  else:
    ew_set_html(page.view, full.cstring)
  page.dirty = true

proc page_query*(self: Sign, selector: string): int =
  defer:
    check()
  int ew_query(self.page.view, selector.cstring).uint64

proc page_create*(self: Sign, tag: string): int =
  defer:
    check()
  int ew_create_element(self.page.view, tag.cstring).uint64

proc page_append*(self: Sign, parent: int, child: int) =
  defer:
    check()
  let page = self.page
  ew_append(page.view, NodeId(parent), NodeId(child))
  page.dirty = true

proc page_remove*(self: Sign, node: int) =
  defer:
    check()
  let page = self.page
  ew_remove(page.view, NodeId(node))
  page.dirty = true

proc page_text*(self: Sign, node: int): string =
  defer:
    check()
  $ew_get_text(self.page.view, NodeId(node))

proc page_set_text*(self: Sign, node: int, text: string) =
  defer:
    check()
  let page = self.page
  ew_set_text(page.view, NodeId(node), text.cstring)
  page.dirty = true

proc page_attr*(self: Sign, node: int, name: string): string =
  defer:
    check()
  self.page.view.get_attribute(NodeId(node), name)

proc page_set_attr*(self: Sign, node: int, name: string, value: string) =
  defer:
    check()
  let page = self.page
  ew_set_attribute(page.view, NodeId(node), name.cstring, value.cstring)
  page.dirty = true

proc page_set_inner_html*(self: Sign, node: int, html: string) =
  defer:
    check()
  let page = self.page
  ew_set_inner_html(page.view, NodeId(node), html.cstring)
  page.dirty = true

proc page_parent*(self: Sign, node: int): int =
  defer:
    check()
  int ew_parent(self.page.view, NodeId(node)).uint64

proc page_rect*(self: Sign, node: int): PageRect =
  defer:
    check()
  var r: array[4, float32]
  ew_rect(self.page.view, NodeId(node), r.addr)
  (r[0].float, r[1].float, r[2].float, r[3].float)

proc page_click_count*(self: Sign, node: int): int =
  defer:
    check()
  ## Clicks this tick on `node` or anything inside it.
  let page = self.page
  for target in page.clicks:
    var n = NodeId(target)
    while n != NO_NODE:
      if n == NodeId(node):
        inc result
        break
      n = ew_parent(page.view, n)

proc summary(times: seq[float]): string =
  if times.len == 0:
    return "none"
  let sorted = times.sorted
  &"n={times.len} median={sorted[sorted.len div 2]:.2f}ms " &
    &"p95={sorted[min(sorted.high, int(ceil(sorted.len.float * 0.95)) - 1)]:.2f}ms " &
    &"max={sorted[^1]:.2f}ms"

proc page_stats*(): string =
  ## Worker-thread cost of pages since the last call: feeding them pointer
  ## events, and laying out + recording changed ones.
  result = &"present: {present_times.summary}; pointer: {pump_times.summary}"
  present_times.set_len(0)
  pump_times.set_len(0)

proc pump_pages*() =
  ## Before scripts run: apply pointer events from the main thread.
  var gone: seq[string]
  for key, page in pages:
    if page.sign.destroyed:
      gone.add key
      continue
    var events: array[96, float32]
    let n = ew_take_pointer(key.cstring, events[0].addr, 32).int
    if n == 0:
      continue
    let start = get_mono_time()
    for i in 0 ..< n:
      let kind = events[i * 3].uint32
      let x = events[i * 3 + 1] * PAGE_WIDTH.float32
      let y = events[i * 3 + 2] * page.height.float32
      var changed = false
      let clicked = ew_pointer(page.view, kind, x, y, changed.addr)
      if changed:
        page.dirty = true
      if clicked != NO_NODE:
        page.clicks.add int(clicked.uint64)
        # Wake the owner, like a bump does, so its loop sees the click this
        # tick.
        let owner = page.sign.owner
        if ?owner and ?owner.script_ctx:
          owner.script_ctx.timer = get_mono_time()
    log_errors(key)
    pump_times.add (get_mono_time() - start).in_microseconds.float / 1000
  for key in gone:
    ew_view_free(pages[key].view)
    ew_forget(key.cstring)
    pages.del key

proc present_pages*() =
  ## After scripts run: forget this tick's clicks, then lay out and record
  ## pages that changed. Clicks last one tick, like other query results; the
  ## click woke the owner, so its script has seen them.
  for key, page in pages:
    page.clicks.set_len(0)
    if not page.dirty or page.sign.destroyed:
      continue
    let start = get_mono_time()
    let sign = page.sign
    let height =
      if sign.height == 0.0:
        int(ew_content_height(page.view).ceil).clamp(1, MAX_PAGE_HEIGHT)
      else:
        int(PAGE_WIDTH.float * sign.height / sign.width).clamp(1, MAX_PAGE_HEIGHT)
    ew_resize(page.view, PAGE_WIDTH, height.uint32)
    page.height = height
    discard ew_present(page.view, key.cstring)
    log_errors(key)
    page.dirty = false
    present_times.add (get_mono_time() - start).in_microseconds.float / 1000

proc page_post_pointer*(self: Sign, kind: int, u: float, v: float) =
  ## For tests: queue a pointer event the way the main thread does.
  discard ew_post_pointer(self.id.cstring, kind.uint32, u, v)
