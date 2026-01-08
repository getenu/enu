version = "0.2.99"
author = "Scott Wadden"
description = "Logo-like DSL for Godot"
license = "MIT"
install_files = @["enu.nim"]
bin_dir = "app"
src_dir = "src"

requires "https://github.com/getenu/Nim#77d820e1",
  "https://github.com/getenu/godot-nim 0.8.6",
  "https://github.com/getenu/model_citizen 0.19.11",
  "https://github.com/getenu/nanoid.nim >= 0.2.1",
  "https://github.com/treeform/pretty >= 0.2.0", "cligen", "chroma", "markdown",
  "chronicles", "dotenv", "nimibook", "metrics#51f1227", "zippy", "unittest2",
  "https://github.com/dsrw/nim-libbacktrace"
