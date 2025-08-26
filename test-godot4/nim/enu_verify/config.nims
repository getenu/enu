# Buildconf, default settings (includes a few required settings) is in.
# Every settings you want can overwrite in a general way.
# All functions defined here are simply wrappers for the switch function,
# so raw switch can be used instead
import gdext/buildconf
import std/strutils

--path: src

let setting = BuildSettings(
  name: capitalizeAscii "enu_verify"
)

configure(setting)