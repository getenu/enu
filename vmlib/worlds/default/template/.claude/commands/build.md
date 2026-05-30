Build a structure in this Enu level: $ARGUMENTS

Steps:
1. `get_level_dir` to get LEVEL_DIR, then `screenshot` (with pitch=-30 or -90 for top-down) to see the current state
2. Plan the structure. Use `box`, `sphere`, `cylinder`, `wall`, `floor`, `place` for geometric shapes; use movement-based drawing (`forward/right/up/turn`) for paths and outlines
3. Pick a unique ID: `build_<descriptive_name>` (lowercase, no spaces)
4. Create `LEVEL_DIR/data/<id>/<id>.json` with the build's world origin and `start_color`; use `"edits": {"<id>": []}` if all blocks come from the script
5. Write `LEVEL_DIR/scripts/<id>.nim` with the build script
6. Touch both files, wait 5 seconds, `screenshot` to verify (Enu auto-detects and loads them)
7. Iterate until it looks right

Positioning: set the JSON `origin` to place the build in world space. Script coordinates are local (relative to origin).

If the structure is purely static voxels with no animation or parameters, you can skip the script and add all blocks directly in the JSON `edits` array.
