import testing

let a = say("a", width = 4.0, height = 2.0)
let b = say("b", width = 4.0, height = 2.0)

proc board(n: int): Page =
  page:
    h1 "Count " & $n

suite "Page values":
  test "one page on two signs":
    let shared = page:
      h1 "Shared"
    a.page = shared
    b.page = shared
    check a["h1"].text == "Shared"
    check b["h1"].text == "Shared"

  test "describing a page again changes every sign showing it":
    a.page = board(1)
    b.page = board(1)
    discard board(2)
    check a["h1"].text == "Count 2"
    check b["h1"].text == "Count 2"

  test "a click on either sign counts":
    var clicks = 0
    var passes = 0
    loop:
      inc passes
      let p = page:
        button(id = "go", style = "width: 100%; height: 300px"):
          text "Go"
          on click:
            inc clicks
      a.page = p
      b.page = p
      if passes == 2:
        b.page_post_pointer(1, 0.5, 0.5)
        b.page_post_pointer(2, 0.5, 0.5)
        a.page_post_pointer(1, 0.5, 0.5)
        a.page_post_pointer(2, 0.5, 0.5)
      if clicks >= 2 or passes >= 20:
        break
    check clicks == 2

  test "html= stops showing the page":
    a.page = board(3)
    b.page = board(3)
    a.html = "<h1>Own</h1>"
    discard board(4)
    check a["h1"].text == "Own"
    check b["h1"].text == "Count 4"

  test "md and raw add to a page, and clicks still find their element":
    var clicks = 0
    var passes = 0
    loop:
      inc passes
      a.page = page:
        md "# Shop\nEverything is *half price*."
        raw "<p class=note>Probably.</p>"
        button(id = "buy", style = "width: 100%; height: 300px"):
          text "Buy"
          on click:
            inc clicks
      if passes == 2:
        a.page_post_pointer(1, 0.5, 0.95)
        a.page_post_pointer(2, 0.5, 0.95)
      if clicks >= 1 or passes >= 20:
        break
    check a["h1"].text == "Shop"
    check a["em"].text == "half price"
    check a[".note"].text == "Probably."
    check clicks == 1

suite "Saying nothing":
  test "say \"\" makes an empty sign, and say() puts it away":
    let empty = say("", width = 2.0)
    check ?empty
    check empty.message == ""
    check empty.show
    say()
    check not empty.show

test_summary()
