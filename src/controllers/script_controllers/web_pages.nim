## Every sign is a page, and every page lives on the worker thread. Each tick
## the worker feeds pages the pointer events the main thread posted, and
## records any page that changed for the render thread (rust/pages/src/hub.rs).
## The main thread only uploads finished frames.
##
## A page shows a description (see page_tree), from one of three places:
##
## - A plain sign's message, as markdown (or HTML).
## - A script on this machine: `page:` describes one, and `html=` and DOM calls
##   change the document directly, with no frame delay. Either way the result
##   goes on `sign.page` as a description, which syncs like any other field.
## - A script on another machine: `sign.page`, as it arrived. Clicks on these
##   go back to that machine through the player's `page_clicks`.
##
## Changes are applied as differences, so a page that changes keeps whatever
## didn't, hover and press states included.

import std/[tables, monotimes, times, strformat, algorithm, math, strutils, sequtils, uri]
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
    ## A page with no changes or pointer activity for this long drops its
    ## document (a few MB) and keeps only its description. Any pointer event,
    ## change, or DOM call rebuilds it.
  sign_page_seconds {.intdefine.} = 30
    ## The same for a plain sign's page, which is cheap to rebuild from its
    ## message.
  PAGE_ROOT = "enu-page"
  RECENT_CLICKS = 16 ## kept in `page_clicks`
  HTML_CACHE_SIZE = 256

type
  PageRect* = tuple[x, y, width, height: float]

  PageSource = enum
    MESSAGE ## a plain sign's message
    SCRIPT ## a script on this machine
    REMOTE ## a script on another machine, through `sign.page`

  Page = ref object
    view: ViewPtr
    sign: Sign
    width: int
    height: int
    scale: float32
    font_px: float
    panel: bool ## the right panel's page, not a sign's
    dirty: bool
    clicks: seq[int]
    clicks_since: MonoTime ## when the oldest unseen click arrived
    clicks_seen: bool ## the script asked about clicks since they arrived
    tree: PageTree
      ## What the page shows. For a page changed by DOM calls, what it showed
      ## when last described, so clicks from other players find their element.
    source: PageSource
    built_from: string
      ## The message (and size) or description the page was last built from.
    imperative: bool
      ## Changed by DOM calls, so it can't be rebuilt from a description.
    parked: bool ## document dropped; `tree` holds the last description
    last_active: MonoTime

  PageDef = ref object
    ## A page made with `page:`, shown on any number of signs. Each sign has
    ## its own document, at its own size, built from the same description.
    tokens: string
    kids: seq[VNode]
    owner: Thing ## the thing whose script describes it
    signs: seq[Sign]

var
  pages {.threadvar.}: Table[string, Page]
  defs {.threadvar.}: Table[string, PageDef]
  showing {.threadvar.}: Table[string, string]
    ## sign id -> the key of the page it shows
  html_cache {.threadvar.}: Table[string, string]
    ## HTML (or markdown) -> its description, for `md` and `raw`
  clicks_sent {.threadvar.}: int64
  clicks_read {.threadvar.}: Table[string, int64]
    ## player id -> the last of their `page_clicks` handled here
  present_times {.threadvar.}: seq[float]
  pump_times {.threadvar.}: seq[float]
  describe_times {.threadvar.}: seq[float]

proc check() =
  ## Turns a failed call into a script error.
  let error = take_error()
  if error != "":
    raise ValueError.init("The page had a problem: " & error)

proc log_errors(key: string) =
  let error = take_error()
  if error != "":
    error "page error", sign = key, error

proc page_font_px(self: Sign): float =
  # Code views have always used a fixed size, whatever the sign's `size`.
  if self.text_only: CODE_FONT_PX else: font_px(self.size, self.width)

proc root_html(self: Sign): string =
  sign_html("<div id=" & PAGE_ROOT & "></div>", self.page_font_px)

proc message_key(self: Sign): string =
  ## Everything a plain sign's page depends on.
  &"{self.message}\0{self.size}\0{self.width}\0{self.height}\0{self.text_only}"

proc root(page: Page): NodeId =
  ew_query(page.view, cstring("#" & PAGE_ROOT))

proc unpark(page: Page) =
  ## Rebuilds a parked page's document from its last description.
  page.view = ew_view_new(page.sign.root_html.cstring, PAGE_WIDTH, PAGE_WIDTH, 1.0)
  let kids = if page.tree.root.is_nil: @[] else: page.tree.root.kids
  page.tree = PageTree()
  discard page.tree.render(page.view, page.root, kids)
  discard page.tree.take_edits
  page.parked = false
  page.dirty = true
  page.last_active = get_mono_time()

proc park(page: Page, key: string) =
  ew_view_free(page.view)
  page.view = ViewPtr(nil)
  page.parked = true
  ew_drop_frame(key.cstring)

proc live_page(self: Sign): Page =
  ## The sign's page, with its document.
  result = pages.get_or_default(self.id)
  if result.is_nil:
    raise ValueError.init(
      "This sign isn't a page yet. Set its `html` first."
    )
  if result.parked:
    result.unpark

proc changed_by_script(self: Sign): Page =
  ## The page, about to be changed by a DOM call.
  result = self.live_page
  result.imperative = true
  result.source = SCRIPT
  result.dirty = true

proc unshow(self: Sign) =
  ## The sign stops showing a `page:` page.
  let key = showing.get_or_default(self.id)
  if key != "":
    showing.del self.id
    if key in defs:
      defs[key].signs.keep_it_if(it != self)

proc create_page(self: Sign, html: string): Page =
  ## A new document for the sign's page, from `html` in Enu's style.
  let px = self.page_font_px
  let full = sign_html(html, px)
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
      result.view = ew_view_new(full.cstring, PAGE_WIDTH, PAGE_WIDTH, 1.0)
      result.parked = false
    else:
      ew_set_html(result.view, full.cstring)
  result.font_px = px
  result.tree = PageTree()
  result.imperative = false
  result.built_from = ""
  result.dirty = true
  result.last_active = get_mono_time()

proc show(self: Sign, kids: seq[VNode], source: PageSource): Page =
  ## Makes the sign's page show a description.
  result = pages.get_or_default(self.id)
  let fresh =
    result.is_nil or result.imperative or result.font_px != self.page_font_px
  if not fresh and not result.tree.root.is_nil and
      same_kids(result.tree.root.kids, kids):
    result.source = source
    return # unchanged: nothing to do, and a parked page stays parked
  if fresh:
    result = self.create_page("<div id=" & PAGE_ROOT & "></div>")
  elif result.parked:
    result.unpark
  result.source = source
  if result.tree.render(result.view, result.root, kids):
    result.dirty = true
    result.last_active = get_mono_time()
  discard result.tree.take_edits

proc publish(self: Sign, description: string) =
  ## Puts what the sign shows where every player's copy can see it.
  if self.page != description:
    self.page = description

proc page_set_html*(self: Sign, html: string) =
  self.unshow
  defer:
    check()
  let page = self.create_page(html)
  page.imperative = true
  page.source = SCRIPT

proc page_query*(self: Sign, selector: string): int =
  defer:
    check()
  int ew_query(self.live_page.view, selector.cstring).uint64

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
  $ew_get_text(self.live_page.view, NodeId(node))

proc page_set_text*(self: Sign, node: int, text: string) =
  defer:
    check()
  let page = self.changed_by_script
  ew_set_text(page.view, NodeId(node), text.cstring)

proc page_attr*(self: Sign, node: int, name: string): string =
  defer:
    check()
  self.live_page.view.get_attribute(NodeId(node), name)

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
  int ew_parent(self.live_page.view, NodeId(node)).uint64

proc page_rect*(self: Sign, node: int): PageRect =
  defer:
    check()
  var r: array[4, float32]
  ew_rect(self.live_page.view, NodeId(node), r.addr)
  (r[0].float, r[1].float, r[2].float, r[3].float)

proc page_click_count*(self: Sign, node: int): int =
  defer:
    check()
  ## Clicks this tick on `node` or anything inside it.
  let page = self.live_page
  page.clicks_seen = true
  for target in page.clicks:
    var n = NodeId(target)
    while n != NO_NODE:
      if n == NodeId(node):
        inc result
        break
      n = ew_parent(page.view, n)

proc page_html_tokens*(text: string, markdown: bool): string =
  ## For `md` and `raw` in a page: HTML (or markdown) as a description.
  defer:
    check()
  let key = (if markdown: "m" else: "h") & text
  result = html_cache.get_or_default(key)
  if result == "" and key notin html_cache:
    let html = if markdown: markdown_html(text) else: text
    result = $ew_describe_html(html.cstring)
    if html_cache.len >= HTML_CACHE_SIZE:
      html_cache.clear
    html_cache[key] = result

proc def_for(key: string): PageDef =
  result = defs.get_or_default(key)
  if result.is_nil:
    result = PageDef()
    defs[key] = result

proc show(self: Sign, def: PageDef) =
  discard self.show(def.kids, SCRIPT)
  self.publish(def.tokens)

proc page_describe*(key: string, owner: Thing, tree: string) =
  ## Records what the page at `key` looks like now, from `page:`, and brings
  ## the signs showing it up to date.
  defer:
    check()
  let def = def_for(key)
  def.owner = owner
  def.signs.keep_it_if(not it.destroyed)
  if tree == def.tokens and def.kids.len > 0:
    return
  def.tokens = tree
  def.kids = parse_tree(tree)
  for sign in def.signs:
    sign.show(def)

proc page_show*(self: Sign, key: string) =
  ## `sign.page = some_page`.
  defer:
    check()
  if showing.get_or_default(self.id) != key:
    self.unshow
    showing[self.id] = key
    def_for(key).signs.add self
  self.show(def_for(key))

proc drop_def(key: string) =
  ## Signs still showing it keep their last picture.
  for sign in defs[key].signs:
    showing.del sign.id
  defs.del key

proc forget_pages*(owner: Thing) =
  ## Before `owner`'s script runs again: pages it described that nothing shows.
  ## The new run describes the ones it still makes, perhaps at new call sites,
  ## which are new keys.
  var unused: seq[string]
  for key, def in defs:
    if def.owner == owner and def.signs.len == 0:
      unused.add key
  for key in unused:
    drop_def key

proc page_key_clicks*(key: string, path: string): int =
  ## Clicks this tick on the described element at `path`, or inside it, on
  ## any sign showing the page.
  defer:
    check()
  let def = defs.get_or_default(key)
  if def.is_nil:
    return
  for sign in def.signs:
    let page = pages.get_or_default(sign.id)
    if not page.is_nil and not page.parked:
      page.clicks_seen = true
      result += page.tree.clicks_at(page.view, page.clicks, path)

proc summary(times: seq[float]): string =
  if times.len == 0:
    return "none"
  let sorted = times.sorted
  &"n={times.len} median={sorted[sorted.len div 2]:.2f}ms " &
    &"p95={sorted[min(sorted.high, int(ceil(sorted.len.float * 0.95)) - 1)]:.2f}ms " &
    &"max={sorted[^1]:.2f}ms"

proc page_stats*(): string =
  ## Worker-thread cost of pages since the last call: feeding them pointer
  ## events, laying out + recording changed ones, and describing pages
  ## changed by DOM calls for other players.
  result =
    &"present: {present_times.summary}; pointer: {pump_times.summary}; " &
    &"describe: {describe_times.summary}"
  present_times.set_len(0)
  pump_times.set_len(0)
  describe_times.set_len(0)

proc link_at(page: Page, node: NodeId): string =
  ## The link clicked, if any, as written: markdown escapes link targets, and
  ## ours are code (`nim://player.tools = {...}`).
  var n = node
  while n != NO_NODE:
    let href = page.view.get_attribute(n, "href")
    if href != "":
      return href.decode_url(decode_plus = false)
    n = ew_parent(page.view, n)

proc follow_link(owner: Thing, href: string) =
  ## Old-style links in a sign's `more`: `nim://` runs code in the sign's
  ## owner, `thing://` opens a thing's code. Run after the pages are pumped:
  ## the code can do anything, like reloading the level.
  if href.starts_with("nim://"):
    owner.eval = href["nim://".len ..^ 1]
  elif href.starts_with("thing://"):
    let id = href["thing://".len ..^ 1]
    state.things.value.walk_tree proc(thing: Thing) =
      if thing.id == id:
        state.player.coding = thing
  else:
    warn "links to pages outside Enu aren't supported yet", href

proc add_click(page: Page, node: NodeId, now: MonoTime) =
  if page.clicks.len == 0:
    page.clicks_since = now
  page.clicks.add int(node.uint64)
  # Wake the thing whose script handles it, like a bump does, so its loop sees
  # the click this tick.
  let key = showing.get_or_default(page.sign.id)
  let owner =
    if key in defs and ?defs[key].owner: defs[key].owner
    else: page.sign.owner
  if ?owner and ?owner.script_ctx:
    owner.script_ctx.timer = now

proc send_click(page: Page, node: NodeId) =
  ## A click on a page built on another machine goes back to it.
  let path = page.tree.path_of(page.view, node)
  if path == "":
    return
  clicks_sent = max(clicks_sent + 1, get_time().to_unix * 1000)
  var lines = state.player.page_clicks.split_lines.filter_it(it != "")
  lines.add [$clicks_sent, page.sign.id, path].join($FIELD_SEP)
  if lines.len > RECENT_CLICKS:
    lines = lines[^RECENT_CLICKS .. ^1]
  state.player.page_clicks = lines.join("\n")

proc read_clicks(player: Player, now: MonoTime) =
  ## Clicks another player made on pages built here.
  var newest = clicks_read.get_or_default(player.id, -1)
  let first = newest < 0
  for line in player.page_clicks.split_lines:
    let fields = line.split(FIELD_SEP)
    if fields.len != 3:
      continue
    let serial = parse_biggest_int(fields[0])
    if serial <= newest:
      continue
    newest = serial
    if first:
      continue # from before we were watching
    let page = pages.get_or_default(fields[1])
    if page.is_nil or page.source != SCRIPT:
      continue
    if page.parked:
      page.unpark
    let node = page.tree.node_at(fields[2])
    if node != NO_NODE:
      page.last_active = now
      page.add_click(node, now)
  clicks_read[player.id] = max(newest, 0)

proc pump_pages*() =
  ## Before scripts run: apply pointer events from the main thread, and clicks
  ## other players made.
  let now = get_mono_time()
  for thing in state.things.value:
    if thing of Player and thing != state.player:
      Player(thing).read_clicks(now)
  var gone: seq[string]
  var links: seq[(Thing, string)]
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
      if clicked == NO_NODE:
        continue
      if page.panel:
        let href = page.link_at(clicked)
        if href != "":
          links.add (page.sign.owner, href)
      elif page.source == REMOTE:
        page.send_click(clicked)
      else:
        page.add_click(clicked, start)
    if page.panel:
      # For the panel's cursor: a hand over links.
      ew_set_pointing(key.cstring, ew_view_pointing(page.view))
    log_errors(key)
    pump_times.add (get_mono_time() - start).in_microseconds.float / 1000
  for key in gone:
    pages[key].sign.unshow
    if not pages[key].parked:
      ew_view_free(pages[key].view)
    ew_forget(key.cstring)
    pages.del key
  var orphans: seq[string]
  for key, def in defs:
    if ?def.owner and def.owner.destroyed:
      orphans.add key
  for key in orphans:
    drop_def key
  for (owner, href) in links:
    owner.follow_link(href)

proc sync_sign(sign: Sign) =
  ## Keeps a sign's page showing its message, or a page built on another
  ## machine. Pages built here are kept up to date as they change.
  if sign.destroyed:
    return
  var page = pages.get_or_default(sign.id)
  if not page.is_nil and page.source == SCRIPT:
    return
  if sign.page != "":
    if page.is_nil or page.source != REMOTE or page.built_from != sign.page or
        page.font_px != sign.page_font_px:
      page = sign.show(parse_tree(sign.page), REMOTE)
      page.built_from = sign.page
  else:
    let key = sign.message_key
    if page.is_nil or page.source != MESSAGE or page.built_from != key:
      let html = body_html(sign.message, sign.text_only)
      page = sign.show(parse_tree($ew_describe_html(html.cstring)), MESSAGE)
      page.built_from = key
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
      built_from: key,
    )
    pages[PANEL_KEY] = page
    page.dirty = true
  else:
    page.sign = sign
    if page.built_from != key:
      ew_set_html(page.view, html.cstring)
      page.built_from = key
      page.dirty = true
    if page.width != width or page.scale != scale:
      ew_set_scale(page.view, scale)
      page.width = width
      page.scale = scale
      page.dirty = true
  log_errors(PANEL_KEY)

proc describe_for_others(page: Page) =
  ## A page changed by DOM calls has no description of its own, so make one
  ## from the document, for other players. Remembering where each node is lets
  ## their clicks find it.
  let start = get_mono_time()
  let kids = parse_tree($ew_describe(page.view, NO_NODE, true))
  page.tree.adopt(kids)
  page.sign.publish(kids.to_tokens)
  describe_times.add (get_mono_time() - start).in_microseconds.float / 1000

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
        if page.panel or page.imperative: -1
        elif page.source == MESSAGE: sign_page_seconds
        else: page_park_seconds
      if idle_for >= 0 and page.clicks.len == 0 and
          now - page.last_active > init_duration(seconds = idle_for):
        page.park(key)
      continue
    let start = get_mono_time()
    if page.imperative:
      page.describe_for_others
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
