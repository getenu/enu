## Pages: signs that are real web pages. Give a sign some HTML, change any
## part of it from your script, and react when players click.
##
## ```nim
## let board = say("...", width = 6, height = 0)
## board.html = "<h2 id=count>0</h2><button id=add>Add one</button>"
## var count = 0
## loop:
##   if board["#add"].clicked as click:
##     inc count
##     board["#count"].text = $count
## ```
##
## `clicked` is a query, like `Player.hit`: inside a command loop, `as` hands
## out each click once and the loop runs again until they've all been
## handled. A click wakes the thing, so it's handled right away.
##
## Or describe the page, and let Enu work out what changed:
##
## ```nim
## var count = 0
## loop:
##   let counter = page:
##     h2 $count
##     button "Add one":
##       on click:
##         inc count
##   board.page = counter
##   other_board.page = counter # the same page, in two places
## ```
##
## `md` and `raw` add markdown and HTML to a page:
##
## ```nim
## board.page = page:
##   md "# Shop\nEverything is *half price*. Probably."
##   button "Buy":
##     on click:
##       inc sold
## ```
##
## Every player sees the same page, and their clicks count too.

import std/[macros, tables, strutils]
import core, vm_bridge_utils

type
  PageRect* = tuple[x, y, width, height: float]
  Element* = object
    ## A piece of a sign's page: a heading, a button, a paragraph...
    sign*: Sign
    id*: int
    selector*: string

  Click* = ref object of RootObj
    ## A player's click on a page element.
    element*: Element

  Page* = ref object
    ## A page made with `page:`. Show it on a sign with `sign.page = it`;
    ## one page can be on several signs at once, and a click on any of them
    ## counts.
    key*: string

bridged_to_host:
  proc page_set_html(self: Sign, html: string)
  proc page_query(self: Sign, selector: string): int
  proc page_create(self: Sign, tag: string): int
  proc page_append(self: Sign, parent: int, child: int)
  proc page_remove(self: Sign, node: int)
  proc page_text(self: Sign, node: int): string
  proc page_set_text(self: Sign, node: int, text: string)
  proc page_attr(self: Sign, node: int, name: string): string
  proc page_set_attr(self: Sign, node: int, name: string, value: string)
  proc page_set_inner_html(self: Sign, node: int, html: string)
  proc page_parent(self: Sign, node: int): int
  proc page_rect(self: Sign, node: int): PageRect
  proc page_click_count(self: Sign, node: int): int
  proc page_describe(key: string, owner: Thing, tree: string)
  proc page_show(self: Sign, key: string)
  proc page_key_clicks(key: string, path: string): int
  proc page_html_tokens(text: string, markdown: bool): string
  proc page_stats*(): string
    ## How long pages took on the worker since you last asked.
  proc page_parked*(self: Sign): bool
    ## For tests: whether the page has put its document away for now (it
    ## hasn't changed or been pointed at in a while).
  proc page_post_pointer*(self: Sign, kind: int, u: float, v: float)
    ## For tests: pretend a player's pointer did something. `kind` is 0 move,
    ## 1 press, 2 release, 3 leave; `u`, `v` run 0..1 across and down.

proc `html=`*(self: Sign, html: string) =
  ## Turn the sign into a page with this HTML. Replaces anything there.
  self.page_set_html(html)

proc `[]`*(self: Sign, selector: string): Element =
  ## Find the first element on the page that matches a CSS selector:
  ## `board["#score"]`, `board["button"]`, `board[".warning"]`.
  Element(sign: self, id: self.page_query(selector), selector: selector)

proc found(self: Element): Element =
  if self.id == 0:
    raise ValueError.init(
      "There's nothing on the page matching \"" & self.selector & "\"."
    )
  self

proc `?`*(self: Element): bool =
  ## Whether the element was found.
  self.id != 0

proc element*(self: Sign, tag: string, text = ""): Element =
  ## Make a new element (not on the page until you `add` it).
  result = Element(sign: self, id: self.page_create(tag))
  if text != "":
    self.page_set_text(result.id, text)

proc add*(self: Element, child: Element) =
  ## Put `child` inside this element, at the end.
  self.sign.page_append(self.found.id, child.found.id)

proc remove*(self: Element) =
  ## Take the element off the page.
  self.sign.page_remove(self.found.id)

proc text*(self: Element): string =
  ## All the text inside the element.
  self.sign.page_text(self.found.id)

proc `text=`*(self: Element, value: string) =
  ## Replace what's inside the element with this text.
  self.sign.page_set_text(self.found.id, value)

proc `html=`*(self: Element, value: string) =
  ## Replace what's inside the element with this HTML.
  self.sign.page_set_inner_html(self.found.id, value)

proc `[]`*(self: Element, attribute: string): string =
  ## An attribute, like `link["href"]`. Empty if it isn't set.
  self.sign.page_attr(self.found.id, attribute)

proc `[]=`*(self: Element, attribute: string, value: string) =
  ## Set an attribute: `box["class"] = "big red"`,
  ## `box["style"] = "width: 40%"`.
  self.sign.page_set_attr(self.found.id, attribute, value)

proc parent*(self: Element): Element =
  Element(sign: self.sign, id: self.sign.page_parent(self.found.id))

proc rect*(self: Element): PageRect =
  ## Where the element is on the page and how big, in pixels. Always up to
  ## date, even right after a change.
  self.sign.page_rect(self.found.id)

proc clicked*(self: Element): Query[seq[Click]] =
  ## Clicks on the element (or anything inside it) since the last tick. Use
  ## it in a command loop: `if button.clicked as click:`.
  let n = self.sign.page_click_count(self.found.id)
  var clicks: seq[Click]
  for i in 0 ..< n:
    clicks.add Click(element: self)
  Query.init(clicks)

# Declarative pages ---------------------------------------------------------
#
# `page board:` describes the whole page every time the loop runs. Enu
# compares it with last time and changes only what's different.
#
# ```nim
# var count = 0
# loop:
#   page board:
#     h2 "Bolt's Counting Machine"
#     p:
#       text "Count: "
#       b $count
#     button(id = "add"):
#       text "Add one"
#       on click:
#         inc count
#     ul:
#       for bot in Bot.all:
#         li bot.id
# ```
#
# Elements are HTML tags: `h2 "text"`, `p:` for children, attributes as
# `pane(class = "row"):`. `pane` is HTML's `div` (`div` is a Nim keyword).
# `text` adds plain text. `on click:` inside an element runs once per click on
# it (or anything inside it), the same way `if button.clicked as click:` does.
#
# An element with an `id` keeps it as its identity: if it moves, Enu moves it
# instead of rebuilding everything around it, and clicks follow it. Elements
# made in a loop over things (`for bot in Bot.all:`) get the thing's id as
# their identity automatically.
#
# A proc marked `{.piece.}` can describe part of a page, for reuse:
#
# ```nim
# proc stat(label: string, value: int) {.piece.} =
#   pane(class = "stat"):
#     b label
#     text $value
# ```

const
  TOKEN_SEP = '\x1e'
  FIELD_SEP = '\x1f'
  PAGE_TAGS = [
    # text
    "a", "b", "br", "code", "em", "i", "img", "label", "mark", "small", "span",
    "strong", "u",
    # blocks
    "address", "article", "aside", "blockquote", "dd", "details", "dialog", "dl",
    "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3",
    "h4", "h5", "h6", "header", "hgroup", "hr", "legend", "li", "main", "menu",
    "nav", "ol", "p", "pane", "pre", "search", "section", "summary", "ul",
    # other
    "button", "caption", "style", "table", "tbody", "td", "th", "thead", "tr",
  ]

proc html_tag(name: string): string =
  if name == "pane": "div" else: name

type PageBuilder* = ref object
  ## Collects a page's description while a `page` block runs.
  key*: string
  tokens*: string
  counters: seq[int]
  paths: seq[string]
  keys: seq[seq[string]]
  next_key: string
  next_key_depth: int
  next_key_count: int
  handling*: bool ## run `on click` bodies on this pass
  handled*: bool ## an `on click` body ran

var building*: PageBuilder
  ## The page being described, while a `page` block runs.

proc init*(_: type PageBuilder, key: string, handling: bool): PageBuilder =
  PageBuilder(
    key: key, counters: @[0], paths: @[""], keys: @[new_seq[string]()],
    handling: handling,
  )

proc clean(s: string): string =
  s.multi_replace(($TOKEN_SEP, " "), ($FIELD_SEP, " "))

proc join_path(parent, step: string): string =
  if parent == "": step else: parent & "/" & step

proc claim(b: PageBuilder, level: int, key: string) =
  if key in b.keys[level]:
    raise ValueError.init(
      "Two elements next to each other have the id \"" & key &
        "\". Ids have to be different."
    )
  b.keys[level].add key

proc open*(b: PageBuilder, tag: string) =
  let i = b.counters[^1]
  inc b.counters[^1]
  var step = $i
  b.tokens.add "E" & FIELD_SEP & tag & TOKEN_SEP
  if b.next_key != "" and b.paths.len == b.next_key_depth:
    let key =
      if b.next_key_count == 0: b.next_key
      else: b.next_key & "~" & $b.next_key_count
    inc b.next_key_count
    b.claim(b.keys.high, key)
    b.tokens.add "K" & FIELD_SEP & key.clean & TOKEN_SEP
    step = "#" & key
  b.counters.add 0
  b.paths.add join_path(b.paths[^1], step)
  b.keys.add new_seq[string]()

proc attr*(b: PageBuilder, name, value: string) =
  b.tokens.add "A" & FIELD_SEP & name.clean & FIELD_SEP & value.clean & TOKEN_SEP
  if name == "id":
    b.claim(b.keys.high - 1, value)
    b.paths[^1] = join_path(b.paths[^2], "#" & value)

proc text*(b: PageBuilder, value: string) =
  inc b.counters[^1]
  b.tokens.add "T" & FIELD_SEP & value.clean & TOKEN_SEP

proc splice*(b: PageBuilder, tokens: string) =
  ## Adds an already made description: one from HTML or markdown.
  b.tokens.add tokens
  var depth = 0
  for token in tokens.split(TOKEN_SEP):
    if token.len == 0:
      continue
    case token[0]
    of 'E':
      if depth == 0:
        inc b.counters[^1]
      inc depth
    of 'T':
      if depth == 0:
        inc b.counters[^1]
    of 'C':
      dec depth
    else:
      discard

proc close*(b: PageBuilder) =
  b.tokens.add "C" & TOKEN_SEP
  discard b.counters.pop
  discard b.paths.pop
  discard b.keys.pop

proc item_key*(b: PageBuilder, key: string) =
  ## Elements opened next at this level take `key` as their identity.
  b.next_key = key
  b.next_key_depth = b.paths.len
  b.next_key_count = 0

proc here*(b: PageBuilder): string =
  b.paths[^1]

template page_on_click*(body: untyped) =
  if building.handling:
    if query_run.is_nil:
      raise ObjectConversionDefect.init(
        "`on click` only works in a page inside a command loop"
      )
    let key = "page-click-" & building.key & "-" & building.here
    if not query_run.has_query(key):
      var clicks: seq[RootRef]
      for i in 0 ..< page_key_clicks(building.key, building.here):
        clicks.add Click()
      query_run.query_results(key, "", clicks)
    if not query_run.query_result(key).is_nil:
      building.handled = true
      body

proc page_body(n: NimNode): NimNode =
  ## Turns the statements of a `page` block into builder calls.
  let b = ident"building"
  case n.kind
  of nnk_stmt_list:
    result = new_stmt_list()
    for child in n:
      result.add page_body(child)
  of nnk_ident:
    if n.str_val in PAGE_TAGS:
      let tag = html_tag(n.str_val)
      result = quote:
        `b`.open(`tag`)
        `b`.close()
    else:
      result = n
  of nnk_call, nnk_command:
    let head = n[0]
    if head.kind != nnk_ident:
      return n
    let name = head.str_val
    if name == "text" and n.len == 2:
      let value = n[1]
      result = quote:
        `b`.text($(`value`))
    elif name == "on" and n.len == 3 and n[1].eq_ident("click") and
        n[2].kind == nnk_stmt_list:
      let body = n[2]
      result = quote:
        page_on_click(`body`)
    elif name in PAGE_TAGS:
      let tag = html_tag(name)
      result = new_stmt_list()
      result.add quote do:
        `b`.open(`tag`)
      var rest = new_stmt_list()
      for arg in n[1 ..^ 1]:
        case arg.kind
        of nnk_expr_eq_expr:
          let key = arg[0].str_val
          let value = arg[1]
          result.add quote do:
            `b`.attr(`key`, $(`value`))
        of nnk_stmt_list:
          rest.add page_body(arg)
        else:
          rest.add quote do:
            `b`.text($(`arg`))
      result.add rest
      result.add quote do:
        `b`.close()
    else:
      result = n
  of nnk_for_stmt:
    # Elements made for each thing in a loop take the thing's id as their
    # identity.
    result = n.copy_nim_tree
    var body = page_body(n[^1])
    let item = n[^3]
    if item.kind == nnk_ident:
      body.insert 0,
        quote do:
          when `item` is Thing:
            `b`.item_key(`item`.id)
    result[^1] = body
    result = new_stmt_list(result)
    result.add quote do:
      `b`.item_key("")
  of nnk_if_stmt, nnk_when_stmt, nnk_case_stmt, nnk_elif_branch, nnk_else,
      nnk_of_branch, nnk_while_stmt, nnk_block_stmt:
    result = n.copy_nim_tree
    for i, child in result:
      if child.kind in {
        nnk_stmt_list, nnk_elif_branch, nnk_else, nnk_of_branch
      }:
        result[i] = page_body(child)
  else:
    result = n

proc describe_page(key: NimNode, body: NimNode): NimNode =
  let first = page_body(body)
  let again = page_body(body.copy_nim_tree)
  result = quote:
    block:
      let outer = building
      try:
        building = PageBuilder.init(`key`, handling = true)
        block:
          `first`
        if building.handled:
          # A click changed something: describe the page again so it shows
          # the change now, not on the next pass.
          building = PageBuilder.init(`key`, handling = false)
          block:
            `again`
        page_describe(building.key, active_thing(), building.tokens)
        Page(key: building.key)
      finally:
        building = outer

proc `page=`*(self: Sign, page: Page) =
  ## Shows `page` on the sign, instead of its message.
  self.page_show(page.key)

macro page*(args: varargs[untyped]): untyped =
  ## `page:` makes a page, described the same way as with `page sign:`.
  ## Inside a command loop it's described again on each pass, and it stays
  ## the same page. `page sign:` describes the whole page for `sign`; see the
  ## notes above.
  if args.len == 1:
    let site = args[0].lineinfo_obj
    let at = ":" & site.filename & ":" & $site.line & ":" & $site.column
    let key = quote:
      active_thing().id & `at`
    result = describe_page(key, args[0])
  elif args.len == 2:
    let sign = args[0]
    let key = quote:
      `sign`.id
    let made = describe_page(key, args[1])
    result = quote:
      `sign`.page = `made`
  else:
    error("`page` takes a block, or a sign and a block", args)

proc md*(markdown: string) =
  ## Markdown in a page, like a sign's message:
  ##
  ## ```nim
  ## page:
  ##   md "# Shop\nEverything is *half price*."
  ##   button "Buy"
  ## ```
  if building.is_nil:
    raise ValueError.init("`md` adds to a page, so call it inside a `page` block.")
  building.splice(page_html_tokens(markdown, true))

proc raw*(html: string) =
  ## HTML in a page, as it is.
  if building.is_nil:
    raise ValueError.init("`raw` adds to a page, so call it inside a `page` block.")
  building.splice(page_html_tokens(html, false))

macro piece*(def: untyped): untyped =
  ## For a proc that describes part of a page: `proc stat(...) {.piece.} =`.
  ## Its body uses the same tags as a `page` block, and it has to be called
  ## from inside one.
  result = def
  let message =
    "`" & $def.name & "` adds to a page, so call it inside a `page` block."
  let body = page_body(def.body)
  result.body = quote:
    if building.is_nil:
      raise ValueError.init(`message`)
    `body`
