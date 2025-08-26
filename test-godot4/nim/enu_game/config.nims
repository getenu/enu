import gdext/buildconf
import std/strutils

--path: src

let setting = BuildSettings(
  name: capitalizeAscii "enu_game"
)

configure(setting)