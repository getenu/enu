## Signs' markdown and code: Nim and unlabelled code blocks are highlighted.

import std/strutils
import ../../src/pages/sign_page

block nim_blocks:
  let html = sign_html("```nim\nlet s = \"a<b\" # hi\n```", 20)
  doAssert "<span class=\"k\">let</span>" in html
  doAssert "<span class=\"s\">&quot;a&lt;b&quot;</span>" in html
  doAssert "<span class=\"c\"># hi</span>" in html

block unlabelled_blocks:
  doAssert "<span class=\"n\">1</span>" in sign_html("```\necho 1\n```", 20)

block other_languages:
  let html = sign_html("```py\nx = 1\n```", 20)
  doAssert "x = 1" in html
  doAssert "<span" notin html

block inline_code:
  doAssert "<code>x</code>" in sign_html("a `x` b", 20)

block panel_code:
  doAssert "<span class=\"k\">proc</span>" in panel_html("proc a = discard", true)

block indented_messages:
  # Indented in a script's string, not code.
  let html = sign_html("    # Hi\n    some text", 20)
  doAssert "<h1>Hi</h1>" in html
  doAssert "<pre>" notin html

block text_only:
  let html = sign_html("echo 1", 20, code = true)
  doAssert "<pre><code><span class=\"ln\">1</span>echo <span class=\"n\">1</span></code></pre>" in html

block line_numbers:
  let html = sign_html("```\na\nb\n```", 20)
  doAssert "<span class=\"ln\">2</span>b" in html
  doAssert "<span class=\"ln\">3</span>" notin html

echo "sign_page_test passed"
