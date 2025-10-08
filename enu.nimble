import std/[strformat, strutils, strscans, os, json, sequtils]
import nimble_helpers

version = "0.2.95"
author = "Scott Wadden"
description = "Logo-like DSL for Godot"
license = "MIT"
install_files = @["enu.nim"]
bin_dir = "app/extension/lib"
src_dir = "app/extension"
package_name = "enu"

# Get lib_ext from settings for bin array
let s = settings()
bin = @["enu" & s.lib_ext]

# Get Nim SHA from vendor/nim submodule
let nim_sha = static_exec("git -C vendor/nim rev-parse HEAD").strip()

requires "https://github.com/getenu/Nim#" & nim_sha,
  "https://github.com/getenu/model_citizen 0.19.6",
  "https://github.com/dsrw/nanoid.nim 0.2.1",
  "https://github.com/godot-nim/gdext-nim 0.15.0",
  "https://github.com/godot-nim/gdext-nim?subdir=coronation 0.1.0",
  "https://github.com/treeform/pretty", "cligen 1.9.1", "chroma", "markdown",
  "chronicles", "dotenv", "nimibook", "metrics#51f1227", "zippy", "nph#c6e0316"

# Tasks

task ios_prereqs, "Build godot for ios":
  with_dir "vendor/pcre":
    exec "./configure  --host=arm-apple-darwin10 --target=arm-apple-darwin10"
    exec "make"
  build_godot(target = "iphone", cpu = "arm64")

task ios, "Build ios":
  let s = settings()
  exec &"nim r tools/write_export_presets.nim {s.git_version}"
  exec &"{godot_bin()} --path app --export-pack \"ios\" " & "ios"

task build_godot, "Build godot":
  build_godot()

task build_headless, "build headless godot":
  build_godot(target = "linuxbsd use_static_cpp=no")

task test, "run godot tests":
  let s = settings()
  exec "nim c tests/godot/tnode_factories"
  cd "tests/godot/app"
  exec get_current_dir() /
    &"vendor/godot/bin/godot_server.osx.opt.tools.{s.cpu} --quiet --script tests/tests.gdns"

task import_assets,
  "Import Godot assets. Only required if you're not using the Godot editor":
  p "Importing assets..."
  exec godot_bin() & " --headless app/project.godot --editor --quit"

task clean, "Remove files produced by build":
  let s = settings()
  rm_dir s.generated_dir
  rm_dir ".nimcache"

task edit_then_quit, "Edit project in Godot":
  exec godot_bin() & " --verbose --quit-after 500 app/project.godot &"

task edit, "Edit project in Godot":
  exec godot_bin() & " app/project.godot &"

task start, "Run Enu":
  let args = command_line_params().filter_it(it.starts_with("--")).join(" ")
  start(args)

task build_and_start, "Build and start":
  exec "nimble build"
  start_task()

task generate_bindings, "Generate Godot extension API bindings":
  p "Generating Godot extension API bindings..."
  let extension_api_json = "extension_api.json"
  let generated_dir = "generated"
  rm_dir generated_dir
  mk_dir generated_dir

  with_dir(generated_dir):
    exec &"{godot_bin()} --headless --dump-extension-api"

  exec &"coronation --apisource:{generated_dir}/{extension_api_json} --ifcesource:vendor/godot/core/extension/gdextension_interface.h --outdir:{generated_dir}"

task start_headless, "Run Enu":
  start("--headless --quit-after 1")

task prereqs, "Build godot, download fonts, generate bindings and stdlib":
  verify_envrc_paths()
  build_godot()
  download_fonts()
  copy_fonts()
  copy_nim_stdlib()
  generate_bindings_task()

task dist_prereqs, "Build godot debug and release versions, and download fonts":
  do_dist_prereqs()

task dist_package, "Build distribution binaries":
  do_dist_package()

task dist, "Build distribution":
  dist_prereqs_task()
  dist_package_task()

task docs, "Build docs":
  exec "rm -rf dist/docs"
  with_dir "docs":
    exec "nim r book.nim init"
    exec "nim r book.nim build"
  exec "cp -r docs/book/assets dist/docs"
  exec "cp media/*.{png,webp} dist/docs/assets"

task export_docs, "Build docs and copy them to ../enu-site/docs":
  docs_task()
  exec "rm -rf ../enu-site/docs"
  exec "cp -r dist/docs ../enu-site"

task format, "Format code with nph (skip src/eval.nim)":
  p "Formatting code with nph..."
  exec "find src -name '*.nim' ! -name 'eval.nim' -exec nph {} +"
  exec "find vmlib/enu -name '*.nim' -exec nph {} +"
  exec "find vmlib/worlds -name '*.nim' -exec nph {} +"
  p "Formatting complete!"

task screenshot, "Take a screenshot of Enu":
  start("--screenshot")

task build_all, "Complete build: setup, prereqs, import_assets, build":
  p "Running complete build..."
  exec nimble_exe & " setup"
  prereqs_task()
  import_assets_task()
  exec nimble_exe & " build"
  p "Build complete!"

task dist_all, "Complete distribution build: setup, dist_prereqs, dist_package":
  p "Running complete distribution build..."
  exec nimble_exe & " setup"
  dist_prereqs_task()
  dist_package_task()
  p "Distribution build complete!"
