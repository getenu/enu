#!/usr/bin/env nim r --warnings:off --hints:off
# bits of the build process that don't work from NimScript

import std/[os, cpuinfo, strformat, httpclient]
import pkg/[compiler/nimeval, cligen]
import godotapigen

include "../installer/export_presets.cfg.nimf"
include "../installer/Info.plist.nimf"

const stdlib = find_nim_std_lib_compile_time()

proc core_count() =
  echo count_processors()

proc find_test(test = ""): string =
  try:
    ".last_test".read_file
  except:
    quit("Nothing to do")

proc save_test_file(file: string) =
  write_file(".last_test", file)

proc build_last_test(debug = false) =
  let test = find_test()
  var cmd = "nim c " & test
  if debug:
    cmd = cmd & " --debugger:native"
  quit exec_shell_cmd(cmd)

proc copy_stdlib(destination: string) =
  remove_dir destination
  create_dir destination
  for path in @["core", "pure", "std", "fusion", "system"]:
    copy_dir join_path(stdlib, path), join_path(destination, path)

  for file in @["system.nim", "stdlib.nimble", "system" / "compilation.nim"]:
    copy_file join_path(stdlib, file), join_path(destination, file)

proc run_tests() =
  discard

proc generate_api(directory = "godotapi", json = "api.json") =
  gen_api directory, join_path(directory, json)

proc write_export_presets(enu_version: string) =
  write_file("app/export_presets.cfg", generate_export_presets(enu_version))

proc write_info_plist(enu_version: string) =
  write_file(
    "dist/Enu.app/Contents/Info.plist", generate_info_plist(enu_version)
  )

dispatch_multi [generate_api],
  [core_count],
  [copy_stdlib],
  [write_export_presets],
  [write_info_plist],
  [save_test_file],
  [build_last_test],
  [run_tests]
