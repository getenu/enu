import gdext/buildconf
import std/strutils

let setting = BuildSettings(name: "Enu", extpath: "/dev/null")

configure(setting)

include "../../src/config.nims"
