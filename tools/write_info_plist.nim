#!/usr/bin/env nim r --warnings:off --hints:off
# Generate Info.plist for macOS distribution

import std/[os, strformat]

include "../installer/Info.plist.nimf"

if param_count() < 1:
  echo "Usage: write_info_plist <enu_version>"
  quit(1)

let enu_version = param_str(1)
write_file(
  "dist/Enu.app/Contents/Info.plist", generate_info_plist(enu_version)
)
