## How a sign's text becomes a page: its message on the sign, its `more` in
## the right panel.

import std/[strutils, strformat, xmltree]
import packages/docutils/highlite
from pkg/markdown import nil

const
  PAGE_WIDTH* = 1200 ## px across a sign, whatever its size in blocks
  SIGN_CSS* = """
  html { font-family: "Jost*", "Noto Color Emoji", sans-serif; }
  code, pre { font-family: "IBM Plex Mono", "Noto Color Emoji", monospace; }
  button, input, select, textarea { font: inherit; }
  body {
    margin: 0; padding: 10px 20px; background: #14031dd6; color: #fff;
  }
  h1, h2, h3, h4, h5, h6 { margin: 0.2em 0; color: #96cbfe; }
  p { margin: 0.3em 0; }
  a { color: #c6c5fe; font-weight: bold; text-decoration: none; }
  code { color: #ff73fd; }
  pre {
    background: #000000d6; color: #e0e0e0; margin: 0.4em -20px;
    padding: 0.3em 20px; border-top: 1px solid #ff73fd;
    border-bottom: 1px solid #ff73fd;
  }
  pre code { color: inherit; }
  .k { color: #96cbfe; } .s { color: #a8ff60; } .c { color: #7c7c7c; }
  .n { color: #ff73fd; } .o { color: #ededed; } .p { color: #c6c5fe; }
  hr { border: none; border-top: 1px solid #ffffff40; }
"""
    ## The look of Enu's old signs: a translucent dark purple background,
    ## light blue headings, pink inline code, and code blocks between pink
    ## rules. Code is coloured like the editor (IR_BLACK).

proc highlight_nim*(code: string): string =
  ## `code` as HTML spans for SIGN_CSS's token classes.
  var tokens: GeneralTokenizer
  tokens.init_general_tokenizer(code)
  while true:
    tokens.get_next_token(lang_nim)
    let kind = tokens.kind
    if kind == gt_eof:
      break
    let text = xmltree.escape(code[tokens.start ..< tokens.start + tokens.length])
    let class =
      case kind
      of gt_keyword: "k"
      of gt_string_lit, gt_long_string_lit, gt_char_lit, gt_escape_sequence,
          gt_raw_data: "s"
      of gt_comment, gt_long_comment: "c"
      of gt_dec_number, gt_bin_number, gt_hex_number, gt_oct_number,
          gt_float_number: "n"
      of gt_operator: "o"
      of gt_preprocessor: "p"
      else: ""
    if class == "":
      result.add text
    else:
      result.add &"<span class=\"{class}\">{text}</span>"

proc unescape(html: string): string =
  ## Undoes markdown's escaping of code.
  html.multi_replace(
    ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
    ("&amp;", "&"),
  )

proc highlight_blocks(html: string): string =
  ## Highlights markdown's code blocks: Nim's, and unlabelled ones, which are
  ## Nim too as far as Enu is concerned.
  const
    OPEN = "<pre><code"
    CLOSE = "</code></pre>"
  var at = 0
  while true:
    let start = html.find(OPEN, at)
    if start < 0:
      break
    let tag_end = html.find('>', start + OPEN.len)
    let finish = html.find(CLOSE, tag_end)
    if tag_end < 0 or finish < 0:
      break
    let attrs = html[start + OPEN.len ..< tag_end]
    result.add html[at ..< tag_end + 1]
    let code = html[tag_end + 1 ..< finish]
    if attrs.strip in ["", "class=\"language-nim\""]:
      result.add highlight_nim(code.unescape)
    else:
      result.add code
    result.add CLOSE
    at = finish + CLOSE.len
  result.add html[at .. ^1]

proc markdown_html(md: string): string =
  highlight_blocks(markdown.markdown(md))

proc font_px*(size, width: float): float =
  ## `size` is text height in blocks; `width` is the sign's width in blocks.
  size * PAGE_WIDTH.float / width

proc sign_html*(message: string, font_px: float): string =
  ## Messages that start with a tag are HTML. Anything else is markdown, as
  ## signs have always been.
  let body =
    if message.strip.starts_with("<"): message
    else: markdown_html(message)
  &"<style>:root {{ font-size: {font_px:.1f}px; }}{SIGN_CSS}</style>{body}"

proc panel_html*(more: string, code: bool): string =
  ## A sign's `more`, for the right panel. Sized in CSS px from a 16px base;
  ## the page's scale carries the screen scale and the font size setting.
  ## `code` shows it as Nim code (signs made with `text_only`).
  let body =
    if code: "<pre><code>" & highlight_nim(more) & "</code></pre>"
    elif more.strip.starts_with("<"): more
    else: markdown_html(more)
  &"<style>:root {{ font-size: 16px; }}{SIGN_CSS}</style>{body}"
