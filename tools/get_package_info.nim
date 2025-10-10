## Tool to extract package URL and VCS revision
## Reads from nimble dump output and nimblemeta.json
##
## Usage: nim r tools/get_package_info.nim <package_name>

import std/[json, strutils, os, osproc, strformat]

proc main() =
  if param_count() < 1:
    quit("Usage: get_package_info <package_name>")

  let pkg_name = param_str(1)

  # Run nimble dump and get JSON output
  let (output, exit_code) = exec_cmd_ex(&"nimble dump {pkg_name} --json 2>&1")
  if exit_code != 0:
    quit(&"Failed to run nimble dump {pkg_name} --json")

  # Extract JSON portion (skip warning lines)
  let json_start = output.find("{")
  if json_start < 0:
    quit("Could not find JSON in nimble dump output")

  let json_str = output[json_start .. ^1]
  let data = parse_json(json_str)

  # Get nimblePath and extract package directory
  let nimble_path = data["nimblePath"].get_str()
  let pkg_dir = nimble_path.parent_dir()

  # Read nimblemeta.json
  let meta_file = pkg_dir / "nimblemeta.json"
  if not file_exists(meta_file):
    quit("Could not find " & meta_file)

  let meta_data = parse_json(read_file(meta_file))
  let url = meta_data["metaData"]["url"].get_str()
  let vcs_revision = meta_data["metaData"]["vcsRevision"].get_str()

  # Output with prefixes for easy filtering
  echo "URL=", url
  echo "VCS_REVISION=", vcs_revision

when is_main_module:
  main()
