## Pages: signs that are real web pages. Give a sign some HTML, change any
## part of it from your script, and do things when players click.
##
## ```nim
## let board = say("...", width = 6, height = 0)
## board.html = "<h2 id=count>0</h2><button id=add>Add one</button>"
## var count = 0
## board["#add"].on_click:
##   inc count
##   board["#count"].text = $count
## forever: sleep()
## ```
##
## Click handlers run when the script finishes waiting for something
## (`sleep`, a move, a turn), so keep it alive with a loop. A click cuts a
## plain `sleep()` short, so `forever: sleep()` answers right away. (Spike:
## needs Enu built with `-d:enu_web`.)

import core, vm_bridge_utils

type
  PageRect* = tuple[x, y, width, height: float]
  Element* = object
    ## A piece of a sign's page: a heading, a button, a paragraph...
    sign*: Sign
    id*: int

  Handler = object
    owner: string
    sign: Sign
    sign_id: string
    node: int
    action: proc()

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
  proc page_next_click(self: Sign): int
  proc page_stats*(): string
    ## How long pages took on the worker since you last asked.
  proc page_post_pointer*(self: Sign, kind: int, u: float, v: float)
    ## For tests: pretend a player's pointer did something. `kind` is 0 move,
    ## 1 press, 2 release, 3 leave; `u`, `v` run 0..1 across and down.

var handlers: seq[Handler]

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

proc dispatch_clicks() =
  ## Runs the handlers this script registered for clicks that have happened.
  ## A click goes to the clicked element's handlers, then its parents'.
  var running {.global.} = false
  if running or handlers.len == 0:
    return
  running = true
  defer:
    running = false
  let me = active_thing().id
  var signs: seq[Sign]
  var seen: seq[string]
  for h in handlers:
    if h.owner == me and h.sign_id notin seen:
      seen.add h.sign_id
      signs.add h.sign
  for sign in signs:
    let sign_id = sign.id
    while true:
      var node = sign.page_next_click()
      if node == 0:
        break
      while node != 0:
        for h in handlers:
          if h.owner == me and h.sign_id == sign_id and h.node == node:
            h.action()
        node = sign.page_parent(node)

proc add_click_handler*(self: Element, action: proc()) =
  handlers.add Handler(
    owner: active_thing().id,
    sign: self.sign,
    sign_id: self.sign.id,
    node: self.id,
    action: action,
  )
  yield_hook = dispatch_clicks

template on_click*(self: Element, body: untyped) =
  ## Do something when a player clicks the element (or anything inside it).
  self.add_click_handler(proc() = body)

register_level_reset(
  proc() =
    handlers.set_len(0)
)
