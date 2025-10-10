import gdext/buildconf
import std/[strutils, os]

# we don't actually want the generated gdextension. Just dump it in `generated`.
let setting = BuildSettings(
  name: "Enu",
  extpath: current_source_path().parent_dir() &
    "/../../generated/generated.gdextension"
)

configure(setting)

include "../../src/config.nims"
