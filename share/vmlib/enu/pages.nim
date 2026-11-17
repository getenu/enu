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
## handled. A click wakes the thing, so it's handled right away. (Spike:
## needs Enu built with `-d:enu_web`.)

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
  proc page_render(self: Sign, tree: string)
  proc page_path_clicks(self: Sign, path: string): int
  proc page_edits*(self: Sign): string
    ## The changes the last few page renders made, one per line. For
    ## looking at what a page sends when it changes.
  proc page_stats*(): string
    ## How long pages took on the worker since you last asked.
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
#     button "Add one":
#       on click:
#         inc count
#     ul:
#       for i in 1 .. count:
#         li \"pressed it, now {i}"
# ```
#
# Elements are HTML tags: `h2 "text"`, `p: ...` for children, attributes as
# `div(class = "row"): ...`. `text` adds plain text. `on click:` inside an
# element runs once per click on it (or anything inside it), the same way
# `if button.clicked as click:` does.

const
  TOKEN_SEP = '\x1e'
  FIELD_SEP = '\x1f'
  PAGE_TAGS = [
    "a", "b", "br", "button", "code", "div", "em", "footer", "h1", "h2", "h3",
    "h4", "h5", "h6", "header", "hr", "i", "img", "label", "li", "ol", "p",
    "pre", "section", "small", "span", "strong", "style", "table", "td", "th",
    "tr", "u", "ul",
  ]

type PageBuilder* = object
  sign*: Sign
  tokens*: string
  counters: seq[int]
  paths: seq[string]
  handling*: bool ## run `on click` bodies on this build
  handled*: bool ## an `on click` body ran

proc init*(_: type PageBuilder, sign: Sign, handling: bool): PageBuilder =
  PageBuilder(sign: sign, counters: @[0], paths: @[""], handling: handling)

proc clean(s: string): string =
  s.multi_replace(($TOKEN_SEP, " "), ($FIELD_SEP, " "))

proc next_path(b: var PageBuilder): string =
  let i = b.counters[^1]
  inc b.counters[^1]
  let parent = b.paths[^1]
  if parent == "": $i else: parent & "." & $i

proc open*(b: var PageBuilder, tag: string) =
  let path = b.next_path
  b.tokens.add "E" & FIELD_SEP & tag & TOKEN_SEP
  b.counters.add 0
  b.paths.add path

proc attr*(b: var PageBuilder, name, value: string) =
  b.tokens.add "A" & FIELD_SEP & name.clean & FIELD_SEP & value.clean & TOKEN_SEP

proc text*(b: var PageBuilder, value: string) =
  discard b.next_path
  b.tokens.add "T" & FIELD_SEP & value.clean & TOKEN_SEP

proc close*(b: var PageBuilder) =
  b.tokens.add "C" & TOKEN_SEP
  discard b.counters.pop
  discard b.paths.pop

proc here*(b: PageBuilder): string =
  b.paths[^1]

proc render*(b: PageBuilder) =
  b.sign.page_render(b.tokens)

template page_on_click*(b: var PageBuilder, body: untyped) =
  if b.handling:
    if query_run.is_nil:
      raise ObjectConversionDefect.init(
        "`on click` only works in a page inside a command loop"
      )
    let key = "page-click-" & b.sign.id & "-" & b.here
    if not query_run.has_query(key):
      var clicks: seq[RootRef]
      for i in 0 ..< b.sign.page_path_clicks(b.here):
        clicks.add Click(element: Element(sign: b.sign))
      query_run.query_results(key, "", clicks)
    if not query_run.query_result(key).is_nil:
      b.handled = true
      body

proc page_body(n, b: NimNode): NimNode =
  ## Turns the statements of a `page` block into builder calls.
  case n.kind
  of nnk_stmt_list:
    result = new_stmt_list()
    for child in n:
      result.add page_body(child, b)
  of nnk_ident:
    if n.str_val in PAGE_TAGS:
      let tag = n.str_val
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
        page_on_click(`b`, `body`)
    elif name in PAGE_TAGS:
      result = new_stmt_list()
      result.add quote do:
        `b`.open(`name`)
      var rest = new_stmt_list()
      for arg in n[1 ..^ 1]:
        case arg.kind
        of nnk_expr_eq_expr:
          let key = if arg[0].kind == nnk_ident: arg[0].str_val else: arg[0].str_val
          let value = arg[1]
          result.add quote do:
            `b`.attr(`key`, $(`value`))
        of nnk_stmt_list:
          rest.add page_body(arg, b)
        else:
          rest.add quote do:
            `b`.text($(`arg`))
      result.add rest
      result.add quote do:
        `b`.close()
    else:
      result = n
  of nnk_if_stmt, nnk_when_stmt, nnk_case_stmt, nnk_elif_branch, nnk_else,
      nnk_of_branch, nnk_for_stmt, nnk_while_stmt, nnk_block_stmt:
    result = n.copy_nim_tree
    for i, child in result:
      if child.kind in {
        nnk_stmt_list, nnk_elif_branch, nnk_else, nnk_of_branch
      }:
        result[i] = page_body(child, b)
  else:
    result = n

macro page*(sign: Sign, body: untyped): untyped =
  ## Describe the whole page for `sign`. See the notes above.
  let b = gensym(nsk_var, "page")
  let first = page_body(body, b)
  let again = page_body(body.copy_nim_tree, b)
  result = quote:
    block:
      var `b` = PageBuilder.init(`sign`, handling = true)
      block:
        `first`
      if `b`.handled:
        # A click changed something: describe the page again so it shows
        # the change now, not on the next pass.
        `b` = PageBuilder.init(`sign`, handling = false)
        block:
          `again`
      `b`.render
