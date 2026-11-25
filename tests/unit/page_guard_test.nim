## Panics in the renderer become errors, and a broken page recovers when its
## HTML is set again.
import std/strutils
import ../../src/pages/renderer

let v = ew_view_new("<p id=a>hi</p><canvas id=c></canvas>", 400, 300, 1.0)
doAssert take_error() == ""
ew_set_text(v, NodeId(987654321), "x") # no such node
doAssert "no element" in take_error()
doAssert ew_query(v, "#a") != NO_NODE, "a bad id doesn't break the page"
doAssert take_error() == ""
let c = ew_query(v, "#c")
ew_canvas_fill(v, c, 0xff0000ff'u32) # never attached: panics in Rust
let e1 = take_error()
doAssert "ew_canvas_attach first" in e1, e1
doAssert take_error() == "", "taking clears it"
doAssert ew_query(v, "#a") == NO_NODE, "a broken page refuses calls"
doAssert "set its html again" in take_error()
ew_set_html(v, "<p id=a>back</p>")
doAssert take_error() == ""
doAssert ew_query(v, "#a") != NO_NODE, "setting html recovers"
doAssert $ew_get_text(v, ew_query(v, "#a")) == "back"
ew_view_free(v)
echo "guard ok"
