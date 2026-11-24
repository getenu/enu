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
    discard a.page_edits
    discard b.page_edits
    discard board(2)
    check "Count 2" in a.page_edits
    check "Count 2" in b.page_edits

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
    let p = page:
      h1 "Before"
    a.page = p
    a.html = "<h1>Own</h1>"
    discard page:
      h1 "After"
    discard a.page_edits
    check a["h1"].text == "Own"

test_summary()
