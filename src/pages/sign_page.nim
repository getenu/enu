## How a sign's text becomes a page. Shared by the main thread (signs set by
## `message`) and the worker (pages scripts build), so they look the same.

import std/[strutils, strformat]
from pkg/markdown import nil

const
  PAGE_WIDTH* = 1200 ## px across a sign, whatever its size in blocks
  SIGN_CSS* = """
  html { font-family: "Jost*", sans-serif; }
  code, pre { font-family: "IBM Plex Mono", monospace; }
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
