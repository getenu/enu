## Path-containment guards for script-supplied names and paths.
##
## Auto-loading level scripts pass world/level/thing names and file paths that
## the host joins into real filesystem paths. These helpers keep those joins
## from escaping their base directory — see the load_level, reset_level,
## claim_name, and read_enu_script bridges in host_bridge.

import std/[os, strutils]

proc valid_path_component*(name: string): bool =
  ## True if `name` is a single, non-traversing path segment: non-empty, not
  ## `.`/`..`, not absolute, and free of path separators. Scripts supply
  ## world/level/thing names that get joined into filesystem paths; requiring a
  ## plain segment keeps those joins from escaping their base directory.
  name.len > 0 and name != "." and name != ".." and '/' notin name and
    '\\' notin name and not name.is_absolute

proc is_within*(base, path: string): bool =
  ## True if the fully-resolved `path` equals `base` or is nested under it.
  ## Uses expand_filename so symlinks (e.g. macOS `/var` -> `/private/var`, which
  ## the VM canonicalizes on one side but config.level_dir keeps on the other)
  ## and `..` are resolved on both sides before the prefix comparison. A path
  ## that can't be resolved (doesn't exist) is treated as outside — fail closed.
  let b =
    try:
      base.expand_filename
    except OSError, ValueError:
      return false
  let p =
    try:
      path.expand_filename
    except OSError, ValueError:
      return false
  p == b or p.starts_with(b & $DirSep)
