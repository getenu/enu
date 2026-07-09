## Regression tests for the script-sandbox path guards used by the load_level,
## reset_level, claim_name, and read_enu_script host bridges. If these weaken,
## a level script regains the ability to escape the level/work dir.

import std/os
import unittest2
import controllers/script_controllers/path_safety

suite "valid_path_component (load_level / claim_name guard)":
  test "accepts plain world / level / thing names":
    check valid_path_component("tutorial-1")
    check valid_path_component("default")
    check valid_path_component("build_tree")
    check valid_path_component("bot_aqslupunw4ndq")

  test "rejects empty and dot segments":
    check not valid_path_component("")
    check not valid_path_component(".")
    check not valid_path_component("..")

  test "rejects path separators and traversal":
    check not valid_path_component("a/b")
    check not valid_path_component("../evil")
    check not valid_path_component("../../../../tmp/evil")
    check not valid_path_component("foo/../bar")
    check not valid_path_component("a\\b")

  test "rejects absolute paths":
    check not valid_path_component("/etc/passwd")

proc make_fixture(): string =
  ## root/level/scripts/foo.nim  (inside)   +   root/other/secret.txt (outside)
  let root = get_temp_dir() / ("enu_path_safety_" & $get_current_process_id())
  remove_dir(root)
  create_dir(root / "level" / "scripts")
  write_file(root / "level" / "scripts" / "foo.nim", "discard\n")
  create_dir(root / "other")
  write_file(root / "other" / "secret.txt", "secret\n")
  root

suite "is_within (read_enu_script confinement)":
  test "accepts the level dir itself and nested files":
    let root = make_fixture()
    defer:
      remove_dir(root)
    let base = root / "level"
    check is_within(base, base)
    check is_within(base, base / "scripts")
    check is_within(base, base / "scripts" / "foo.nim")

  test "rejects a real file outside the level dir":
    let root = make_fixture()
    defer:
      remove_dir(root)
    let base = root / "level"
    check not is_within(base, root / "other")
    check not is_within(base, root / "other" / "secret.txt")

  test "rejects traversal that escapes the level dir even to a real file":
    let root = make_fixture()
    defer:
      remove_dir(root)
    let base = root / "level"
    check not is_within(base, base / ".." / "other" / "secret.txt")

  test "fails closed on a path that does not exist":
    let root = make_fixture()
    defer:
      remove_dir(root)
    let base = root / "level"
    check not is_within(base, base / "scripts" / "does_not_exist.nim")
