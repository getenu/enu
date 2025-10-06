#!/usr/bin/env nim r --warnings:off --hints:off
# Generate export presets for Godot

import std/[os, strformat]

include "../installer/export_presets.cfg.nimf"

if param_count() < 1:
  echo "Usage: write_export_presets <enu_version>"
  quit(1)

let enu_version = param_str(1)
write_file("app/export_presets.cfg", generate_export_presets(enu_version))
