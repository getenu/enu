# stupider like a fox!

import std/[strutils, macros]
import pkg/regex

macro patch_line_length() =
  # strip "." from imports, since they're not siblings to this patch file but
  # are on the nim path
  const import_regex = re2(r"import ""\.""\/\[(.*)\]")

  let
    path = "../../deps/nph/src/phrenderer.nim"
    src = static_read path
    og_line_length = "44 else: 88"
    new_line_length = "40 else: 80"
    patched = src.replace(import_regex, "import $1").replace(
        og_line_length, new_line_length
      )

  parse_stmt(patched, path)

patch_line_length()
