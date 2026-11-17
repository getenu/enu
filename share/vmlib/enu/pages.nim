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

import core, vm_bridge_utils

type
  PageRect* = tuple[x, y, width, height: float]
  Element* = object
    ## A piece of a sign's page: a heading, a button, a paragraph...
    sign*: Sign
    id*: int

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
  Element(sign: self, id: self.page_query(selector))

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
  self.sign.page_append(self.id, child.id)

proc remove*(self: Element) =
  ## Take the element off the page.
  self.sign.page_remove(self.id)

proc text*(self: Element): string =
  ## All the text inside the element.
  self.sign.page_text(self.id)

proc `text=`*(self: Element, value: string) =
  ## Replace what's inside the element with this text.
  self.sign.page_set_text(self.id, value)

proc `html=`*(self: Element, value: string) =
  ## Replace what's inside the element with this HTML.
  self.sign.page_set_inner_html(self.id, value)

proc `[]`*(self: Element, attribute: string): string =
  ## An attribute, like `link["href"]`. Empty if it isn't set.
  self.sign.page_attr(self.id, attribute)

proc `[]=`*(self: Element, attribute: string, value: string) =
  ## Set an attribute: `box["class"] = "big red"`,
  ## `box["style"] = "width: 40%"`.
  self.sign.page_set_attr(self.id, attribute, value)

proc parent*(self: Element): Element =
  Element(sign: self.sign, id: self.sign.page_parent(self.id))

proc rect*(self: Element): PageRect =
  ## Where the element is on the page and how big, in pixels. Always up to
  ## date, even right after a change.
  self.sign.page_rect(self.id)

proc clicked*(self: Element): Query[seq[Click]] =
  ## Clicks on the element (or anything inside it) since the last tick. Use
  ## it in a command loop: `if button.clicked as click:`.
  let n = self.sign.page_click_count(self.id)
  var clicks: seq[Click]
  for i in 0 ..< n:
    clicks.add Click(element: self)
  Query.init(clicks)
