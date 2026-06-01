version = "0.2.99"
author = "Scott Wadden"
description = "Logo-like DSL for Godot"
license = "MIT"
install_files = @["enu.nim"]
bin_dir = "app"
src_dir = "src"

requires "https://github.com/getenu/Nim#bea4c144",
  "https://github.com/getenu/godot-nim 0.8.6",
  "https://github.com/getenu/ed >= 0.20.7",
  "https://github.com/getenu/nanoid.nim >= 0.2.1",
  "https://github.com/treeform/pretty >= 0.2.0", "cligen", "chroma", "markdown",
  "chronicles", "dotenv", "nimibook", "metrics#a1296ca", "zippy", "unittest2",
  "https://github.com/getenu/nph#948b933", "regex", "nimcp",
  "https://github.com/gokr/mummyx#32f0ef97",
  "https://github.com/dsrw/nim-libbacktrace"
