## A level switch keeps the VM, so a global in the script API outlives the
## level that set it. Every module-level `var` in share/vmlib/enu has to be
## listed here with why that's fine; a new one fails until it's added.

import std/[os, strutils, sets]
import unittest2

const KNOWN = [
  # set on every call into a script
  "base_bridge.current_active_thing", "base_bridge.last_test_handle",
  "base_bridge.active_handle", "vm_bridge_utils.host_error_pending",
  # registered once, by the API's own modules
  "core.state_init_callbacks", "core.level_reset_callbacks",
  # level things' handles are forgotten by reset_level_state
  "handles.registry",
  # set again by initialize_state on every level load
  "players.player",
  # no per-level state
  "worlds.world", "types.global_default",
  # cleared by a level reset callback
  "builds_private.save_points", "builds_private.warned_about_save",
  # not part of the base API: reset with the level that imported it
  "testing.current_suite", "testing.failed_tests", "testing.failure_msg",
  "testing.passed_tests", "testing.test_failed", "testing.total_tests",
]

# Included into each script rather than imported: its globals are per script.
const INCLUDED = ["loops.nim"]

proc module_vars(path: string): seq[string] =
  var in_block = false
  for line in path.lines:
    if line.starts_with("var "):
      in_block = false
      result.add line[4 ..^ 1].split({':', '=', '*', ' '})[0]
    elif line == "var":
      in_block = true
    elif in_block:
      if line.starts_with("  ") and line.strip.len > 0 and
          not line.strip.starts_with("#"):
        if not line.starts_with("    "):
          result.add line.strip.split({':', '=', '*', ' '})[0]
      elif line.strip.len > 0:
        in_block = false

suite "Script API globals":
  test "every global is known to survive a level switch":
    let dir = current_source_path().parent_dir / "../../share/vmlib/enu"
    var found: HashSet[string]
    for path in walk_files(dir / "*.nim"):
      if path.extract_filename notin INCLUDED:
        for name in module_vars(path):
          found.incl path.split_file.name & "." & name
    check found - KNOWN.to_hash_set == init_hash_set[string]()
    check KNOWN.to_hash_set - found == init_hash_set[string]()
