## How a sign's text becomes a page: its message on the sign, its `more` in
## the right panel.

import std/[strutils, strformat, xmltree]
from pkg/markdown import nil

const
  PAGE_WIDTH* = 1200 ## px across a sign, whatever its size in blocks
  SIGN_CSS* = """
  html { font-family: "Jost*", "Noto Color Emoji", sans-serif; }
  code, pre { font-family: "IBM Plex Mono", "Noto Color Emoji", monospace; }
  button, input, select, textarea { font: inherit; }
  body { margin: 0; padding: 0.35em 0.6em; background: #000000d6; color: #fff; }
  h1, h2, h3 { margin: 0.2em 0; }
  p { margin: 0.3em 0; }
  code { background: #ffffff26; border-radius: 0.2em; padding: 0 0.2em; }
"""

proc font_px*(size, width: float): float =
  ## `size` is text height in blocks; `width` is the sign's width in blocks.
  size * PAGE_WIDTH.float / width

proc sign_html*(message: string, font_px: float): string =
  ## Messages that start with a tag are HTML. Anything else is markdown, as
  ## signs have always been.
  let body =
    if message.strip.starts_with("<"): message
    else: markdown.markdown(message)
  &"<style>:root {{ font-size: {font_px:.1f}px; }}{SIGN_CSS}</style>{body}"

proc panel_html*(more: string, code: bool): string =
  ## A sign's `more`, for the right panel. Sized in CSS px from a 16px base;
  ## the page's scale carries the screen scale and the font size setting.
  ## `code` shows it as Nim code (signs made with `text_only`).
  let body =
    if code: "<pre><code>" & xmltree.escape(more) & "</code></pre>"
    elif more.strip.starts_with("<"): more
    else: markdown.markdown(more)
  &"<style>:root {{ font-size: 16px; }}{SIGN_CSS}</style>{body}"
