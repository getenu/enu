## Every sign is a page, and every page lives on the worker thread. A plain
## sign's page is built from its message; a script can instead build one
## (`html=`, DOM calls, or `page sign:`), reading and changing the DOM directly
## with no frame delay. Each tick the worker feeds pages the pointer events the
## main thread posted, and records any page that changed for the render thread
## (rust/pages/src/hub.rs). The main thread only uploads finished frames.

import std/[tables, monotimes, times, strformat, algorithm, math, strutils]
import core, models/[signs, things]
import ../../pages/[renderer, sign_page, page_tree]

const
  MAX_PAGE_HEIGHT = 4096
    ## Pages don't scroll yet. Taller ones are cut off rather than turned
    ## into huge textures.
  MAX_PANEL_HEIGHT = 16384
    ## The panel scrolls, so its page can be taller.
  PANEL_KEY* = "enu-right-panel"
    ## The right panel's page: the open sign's `more`.
  page_park_seconds {.intdefine.} = 120
    ## A declarative page with no changes or pointer activity for this long
    ## drops its document (a few MB) and keeps only its description. Any
    ## pointer event, change, or DOM call rebuilds it.
  sign_page_seconds {.intdefine.} = 30
    ## The same for a plain sign's page, which is cheap to rebuild from its
    ## message.
  PAGE_ROOT = "enu-page"

type
  PageRect* = tuple[x, y, width, height: float]

  Page = ref object
    view: ViewPtr
    sign: Sign
    width: int
    height: int
    scale: float32
    panel: bool ## the right panel's page, not a sign's
    dirty: bool
    clicks: seq[int]
    clicks_since: MonoTime ## when the oldest unseen click arrived
    clicks_seen: bool ## the script asked about clicks since they arrived
    tree: PageTree ## what `page sign:` last described
    edit_log: seq[string]
    imperative: bool ## changed by DOM calls, so it can't be rebuilt
    message: string
      ## For a plain sign, what its page was built from: the message and the
      ## sign's size. Empty once a script builds the page instead.
    parked: bool ## document dropped; `tree` holds the last description
    last_active: MonoTime

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

proc root_html(self: Sign): string =
  sign_html("<div id=" & PAGE_ROOT & "></div>", font_px(self.size, self.width))

proc message_html(self: Sign): string =
  # Code views have always used a fixed size, whatever the sign's `size`.
  let px = if self.text_only: CODE_FONT_PX else: font_px(self.size, self.width)
  sign_html(self.message, px, self.text_only)

proc message_key(self: Sign): string =
  ## Everything a plain sign's page depends on.
  &"{self.message}\0{self.size}\0{self.width}\0{self.height}\0{self.text_only}"

proc unpark(page: Page) =
  ## Rebuilds a parked page's document from its message or last description.
  if page.message != "":
    page.view =
      ew_view_new(page.sign.message_html.cstring, PAGE_WIDTH, PAGE_WIDTH, 1.0)
  else:
    page.view =
      ew_view_new(page.sign.root_html.cstring, PAGE_WIDTH, PAGE_WIDTH, 1.0)
    let root = ew_query(page.view, cstring("#" & PAGE_ROOT))
    let kids = if page.tree.root.is_nil: @[] else: page.tree.root.kids
    page.tree = PageTree()
    discard page.tree.render(page.view, root, kids)
    discard page.tree.take_edits
  page.parked = false
  page.dirty = true
  page.last_active = get_mono_time()

proc park(page: Page, key: string) =
  ew_view_free(page.view)
  page.view = ViewPtr(nil)
  page.parked = true
  ew_drop_frame(key.cstring)

proc page(self: Sign): Page =
  result = pages.get_or_default(self.id)
  if result.is_nil:
    raise ValueError.init(
      "This sign isn't a page yet. Set its `html` first."
    )
  if result.parked:
    result.unpark

proc changed_by_script(self: Sign): Page =
  ## The page, about to be changed by a DOM call.
  result = self.page
  result.imperative = true
  result.dirty = true

proc create_page(self: Sign, html: string): Page =
  let full = sign_html(html, font_px(self.size, self.width))
  result = pages.get_or_default(self.id)
  if result.is_nil:
    result = Page(
      view: ew_view_new(full.cstring, PAGE_WIDTH, PAGE_WIDTH, 1.0),
      sign: self,
      width: PAGE_WIDTH,
      height: PAGE_WIDTH,
      scale: 1.0,
    )
    pages[self.id] = result
  else:
    if result.parked:
      result.unpark
    ew_set_html(result.view, full.cstring)
  result.tree = PageTree()
  result.message = ""
  result.dirty = true
  result.last_active = get_mono_time()

proc page_set_html*(self: Sign, html: string) =
  defer:
    check()
  self.create_page(html).imperative = true

proc page_query*(self: Sign, selector: string): int =
  defer:
    check()
  int ew_query(self.page.view, selector.cstring).uint64

proc page_create*(self: Sign, tag: string): int =
  defer:
    check()
  int ew_create_element(self.changed_by_script.view, tag.cstring).uint64

proc page_append*(self: Sign, parent: int, child: int) =
  defer:
    check()
  let page = self.changed_by_script
  ew_append(page.view, NodeId(parent), NodeId(child))

proc page_remove*(self: Sign, node: int) =
  defer:
    check()
  let page = self.changed_by_script
  ew_remove(page.view, NodeId(node))

proc page_text*(self: Sign, node: int): string =
  defer:
    check()
  $ew_get_text(self.page.view, NodeId(node))

proc page_set_text*(self: Sign, node: int, text: string) =
  defer:
    check()
  let page = self.changed_by_script
  ew_set_text(page.view, NodeId(node), text.cstring)

proc page_attr*(self: Sign, node: int, name: string): string =
  defer:
    check()
  self.page.view.get_attribute(NodeId(node), name)

proc page_set_attr*(self: Sign, node: int, name: string, value: string) =
  defer:
    check()
  let page = self.changed_by_script
  ew_set_attribute(page.view, NodeId(node), name.cstring, value.cstring)

proc page_set_inner_html*(self: Sign, node: int, html: string) =
  defer:
    check()
  let page = self.changed_by_script
  ew_set_inner_html(page.view, NodeId(node), html.cstring)

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
  page.clicks_seen = true
  for target in page.clicks:
    var n = NodeId(target)
    while n != NO_NODE:
      if n == NodeId(node):
        inc result
        break
      n = ew_parent(page.view, n)

proc page_render*(self: Sign, tree: string) =
  ## Makes the page match a description from `page sign:`.
  defer:
    check()
  let kids = parse_tree(tree)
  var page = pages.get_or_default(self.id)
  if not page.is_nil and not page.imperative and not page.tree.root.is_nil and
      same_kids(page.tree.root.kids, kids):
    return # unchanged: nothing to do, and a parked page stays parked
  if page.is_nil or page.message != "":
    page = self.create_page("<div id=" & PAGE_ROOT & "></div>")
  page = self.page
  var root = ew_query(page.view, cstring("#" & PAGE_ROOT))
  if root == NO_NODE:
    root = ew_create_element(page.view, "div")
    ew_set_attribute(page.view, root, "id", PAGE_ROOT)
    ew_append(page.view, ew_query(page.view, "body"), root)
  if page.tree.render(page.view, root, kids):
    page.dirty = true
    page.last_active = get_mono_time()
    page.edit_log.add page.tree.take_edits
    if page.edit_log.len > 200:
      page.edit_log = page.edit_log[^200 .. ^1]

proc page_path_clicks*(self: Sign, path: string): int =
  ## Clicks this tick on the described element at `path`, or inside it.
  defer:
    check()
  let page = pages.get_or_default(self.id)
  if not page.is_nil and not page.parked:
    page.clicks_seen = true
    result = page.tree.clicks_at(page.view, page.clicks, path)

proc page_edits*(self: Sign): string =
  defer:
    check()
  let page = self.page
  result = page.edit_log.join("\n")
  page.edit_log.set_len(0)

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

proc follow_link(page: Page, node: NodeId) =
  ## Old-style links in a sign's `more`: `nim://` runs code in the sign's
  ## owner, `thing://` opens a thing's code.
  var n = node
  while n != NO_NODE:
    let href = page.view.get_attribute(n, "href")
    if href.starts_with("nim://"):
      page.sign.owner.eval = href["nim://".len ..^ 1]
      return
    elif href.starts_with("thing://"):
      let id = href["thing://".len ..^ 1]
      state.things.value.walk_tree proc(thing: Thing) =
        if thing.id == id:
          state.player.coding = thing
      return
    elif href != "":
      warn "links to pages outside Enu aren't supported yet", href
      return
    n = ew_parent(page.view, n)

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
    if page.parked:
      page.unpark
    page.last_active = start
    for i in 0 ..< n:
      let kind = events[i * 3].uint32
      if kind == POINTER_WAKE:
        # A sign node that needs the picture again (it was recreated).
        page.dirty = true
        continue
      let x = events[i * 3 + 1] * page.width.float32
      let y = events[i * 3 + 2] * page.height.float32
      var changed = false
      let clicked = ew_pointer(page.view, kind, x, y, changed.addr)
      if changed:
        page.dirty = true
      if clicked != NO_NODE and page.panel:
        page.follow_link(clicked)
      elif clicked != NO_NODE:
        if page.clicks.len == 0:
          page.clicks_since = start
        page.clicks.add int(clicked.uint64)
        # Wake the owner, like a bump does, so its loop sees the click this
        # tick.
        let owner = page.sign.owner
        if ?owner and ?owner.script_ctx:
          owner.script_ctx.timer = get_mono_time()
    log_errors(key)
    pump_times.add (get_mono_time() - start).in_microseconds.float / 1000
  for key in gone:
    if not pages[key].parked:
      ew_view_free(pages[key].view)
    ew_forget(key.cstring)
    pages.del key

proc sync_sign(sign: Sign) =
  ## Builds or rebuilds a plain sign's page when its message or size changed.
  if sign.destroyed:
    return
  var page = pages.get_or_default(sign.id)
  if not page.is_nil and page.message == "":
    return # a script built this page
  let key = sign.message_key
  if not page.is_nil and page.message == key:
    return
  if page.is_nil:
    page = Page(
      view: ew_view_new(sign.message_html.cstring, PAGE_WIDTH, PAGE_WIDTH, 1.0),
      sign: sign,
      width: PAGE_WIDTH,
      height: PAGE_WIDTH,
      scale: 1.0,
    )
    pages[sign.id] = page
  elif page.parked:
    page.message = key
    page.unpark
  else:
    ew_set_html(page.view, sign.message_html.cstring)
  page.message = key
  page.dirty = true
  page.last_active = get_mono_time()
  log_errors(sign.id)

proc sync_panel() =
  ## Keeps the right panel's page showing the open sign's `more`, at the
  ## width and scale the panel asked for.
  let sign = state.player.open_sign
  var page = pages.get_or_default(PANEL_KEY)
  if sign.is_nil or sign.more == "":
    if not page.is_nil:
      ew_view_free(page.view)
      ew_drop_frame(PANEL_KEY)
      pages.del PANEL_KEY
    return
  var scale: float32
  let width = ew_requested_size(PANEL_KEY, scale.addr).int
  if width <= 0:
    return # the panel isn't showing yet
  let html = panel_html(sign.more, sign.text_only)
  let key = sign.id & "\0" & html
  if page.is_nil:
    page = Page(
      view: ew_view_new(html.cstring, width.uint32, width.uint32, scale),
      sign: sign,
      width: width,
      height: width,
      scale: scale,
      panel: true,
      message: key,
    )
    pages[PANEL_KEY] = page
    page.dirty = true
  else:
    page.sign = sign
    if page.message != key:
      ew_set_html(page.view, html.cstring)
      page.message = key
      page.dirty = true
    if page.width != width or page.scale != scale:
      ew_set_scale(page.view, scale)
      page.width = width
      page.scale = scale
      page.dirty = true
  log_errors(PANEL_KEY)

proc present_pages*(things: seq[Thing]) =
  ## After scripts run: bring plain signs' pages up to date, forget clicks the
  ## script has seen, lay out and record pages that changed, and park pages
  ## that have been quiet a while.
  things.walk_tree proc(thing: Thing) =
    if thing of Sign:
      sync_sign(Sign(thing))
  sync_panel()
  let now = get_mono_time()
  for key, page in pages:
    # Clicks last until the script has looked at them (its loop may not run
    # every tick, e.g. when the worker is busy), or two seconds if it never
    # does.
    if page.clicks_seen or now - page.clicks_since > init_duration(seconds = 2):
      page.clicks.set_len(0)
    page.clicks_seen = false
    if page.sign.destroyed or page.parked:
      continue
    if not page.dirty:
      let idle_for =
        if page.panel: -1
        elif page.message != "": sign_page_seconds
        elif not page.imperative and not page.tree.root.is_nil: page_park_seconds
        else: -1
      if idle_for >= 0 and page.clicks.len == 0 and
          now - page.last_active > init_duration(seconds = idle_for):
        page.park(key)
      continue
    let start = get_mono_time()
    let sign = page.sign
    if page.panel:
      # Measure at the panel's current width.
      ew_resize(page.view, page.width.uint32, page.height.uint32)
    let height =
      if page.panel:
        int(ew_content_height(page.view).ceil).clamp(1, MAX_PANEL_HEIGHT)
      elif sign.height == 0.0:
        int(ew_content_height(page.view).ceil).clamp(1, MAX_PAGE_HEIGHT)
      else:
        int(PAGE_WIDTH.float * sign.height / sign.width).clamp(1, MAX_PAGE_HEIGHT)
    ew_resize(page.view, page.width.uint32, height.uint32)
    page.height = height
    discard ew_present(page.view, key.cstring)
    log_errors(key)
    page.dirty = false
    present_times.add (get_mono_time() - start).in_microseconds.float / 1000

proc page_parked*(self: Sign): bool =
  ## For tests: whether the page has dropped its document for now.
  let page = pages.get_or_default(self.id)
  not page.is_nil and page.parked

proc page_post_pointer*(self: Sign, kind: int, u: float, v: float) =
  ## For tests: queue a pointer event the way the main thread does.
  discard ew_post_pointer(self.id.cstring, kind.uint32, u, v)
