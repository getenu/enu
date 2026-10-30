version = "0.2.99"
author = "Scott Wadden"
description = "Logo-like DSL for Godot"
license = "MIT"
install_files = @["enu.nim"]
bin_dir = "app"
src_dir = "src"

requires "https://github.com/getenu/Nim#05fa8ee4",
  "godot 0.8.6",
  "ed 0.31.0",
  "nanoid >= 0.2.1",
  "pretty", "cligen", "chroma", "markdown",
  "chronicles", "dotenv", "nimibook", "metrics 0.2.3", "zippy", "unittest2",
  "nph#948b933", "regex",
  "nimcp 0.10.0",
  "mummy#32f0ef97",
  "libbacktrace",
  "osdialog"
