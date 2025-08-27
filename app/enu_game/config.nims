--path: "src"
--path: "../../generated"

import gdext/buildconf
import std/strutils

let setting = BuildSettings(
  name: "EnuGame"
)

configure(setting)
