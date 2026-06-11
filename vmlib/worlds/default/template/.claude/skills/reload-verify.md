# Reload and Verify Changes

Enu hot-reloads script and JSON files. Use this skill to apply changes
and verify them visually with screenshots.

## Usage

```
/reload-verify
```

## Hot-Reload Pattern

After writing JSON or script files:

1. **`wait_for_script(unit_id)`** — reloads the unit if its files
   changed and blocks until the script finishes its run. On success
   returns the unit's world bounds (`bounds: (min) .. (max)`) — check
   them against the footprint you intended (a 1×1×1 box at the origin
   means the script drew nothing). On failure returns the script's
   compile/runtime error with file:line. No sleeps, no mtime games,
   and errors surface in the tool result instead of having to be
   fished out of the console.

2. **Take a screenshot** *and walk through* to verify

Caveats:

- **Animated builds never "finish".** A `loop:` state machine or
  `move me` animation runs forever, so `wait_for_script` reports
  "still running" after the timeout — that means *alive, not stuck*.
  Pass a short timeout (e.g. 5) and verify with bounds or a
  screenshot instead.
- Rarely, a call that lands mid-rebuild returns success with a 1×1×1
  bounds — re-query once before concluding the script drew nothing.
- **Proto dependents go stale.** When a proto script (`name X`) changes,
  scripts that reference `X` keep their previously compiled types and
  fail with type-mismatch errors until they reload too. Touch dependents
  in dependency order: proto → referencing protos → spawners.
- Without MCP, the CLI does the same job: `enu wait_for_script
  --unit_id <id>`. (Manual fallback: `touch` the files and wait 4–5
  seconds — Enu polls every ~2s.)

Hot-reload is a full re-run, not an additive paint. The watcher does
the same thing as the in-game editor: it resets the unit's voxel
state and re-executes the script body. So edits that *remove* or
*move* geometry produce a clean rebuild — touch the file, the unit
matches the new script. Hand-placed JSON `edits` are preserved
through the reset.

### When `save_and_reload` is appropriate

`save_and_reload` reloads the whole level from disk. It's disruptive
to anyone else working in the same level (other agents, the human),
so prefer the per-script touch flow above. Real reasons to reach for
the nuclear option:

- A vmlib change (your edit is to `vmlib/enu/*.nim`, not a level
  script — the running interpreter has stale bindings).
- The level structure itself changed (`level.json` corruption, etc.).
- The agent is debugging Enu engine code and needs a fresh VM.

```nim
press_action("save_and_reload")
```

### Verification is by walk-through, not just screenshot

Screenshots from far back miss most placement bugs (chair clipping a
doorway, counter blocking entry, bed footboard against a wall). The
reliable check:

1. Spawn / move the player into the room
2. Walk through every door from both sides
3. Check that furniture is reachable on all sides it should be (≥ 1 m
   clearance per `/build-plan`)
4. *Then* screenshot for the record

Bot teleports (`set_position`) sometimes snap back when the target
position is inside another object's collision capsule. If the bot ends up
somewhere unexpected, `units_near` will show where it actually landed.

## Positioning the MCP Bot

Move the MCP bot to get a better view of what you're building:

```
set_position x=0 y=15 z=-10 rotation=180
```
- `y=15` lifts the bot to see from above
- `rotation=180` faces south (toward -Z where most content is)

## Check What's in the Level

```nim
# Via eval (output in get_console):
for b in Build.all: echo b.id, " at ", b.position
for bot in Bot.all: echo bot.id, " at ", bot.position
echo "Level: ", level_name()
```

## Verify a Specific Build Exists

```nim
var found = false
for b in Build.all:
  if b.id == "build_my_wall":
    echo "Found at: ", b.position
    found = true
if not found:
  echo "NOT FOUND - check data/<id>/<id>.json exists, then wait_for_script"
```

## Troubleshooting

**Build not appearing:**
- `wait_for_script(unit_id)` — triggers the load and returns the compile
  error if there is one
- Check both files exist: `data/<id>/<id>.json` and `scripts/<id>.nim`
- Verify the JSON file is valid: `python3 -c "import json; json.load(open('path/to/file.json'))"`

**Build looks empty / a part is missing in a screenshot — query the data, don't
trust the screenshot alone:**
- `eval("echo Build(find_by_id(\"build_x\")).bounds")` — `bounds` is the voxels'
  world-space AABB, so it tells you *where and how big* the voxels actually are.
- If `bounds` is far from where you framed, the build is **mispositioned** and
  rendering off-screen — reframe there.
- If `bounds` is much larger than you expect, the geometry is genuinely too big
  — re-check your voxel dimensions × `scale`.
- If `bounds` looks right but nothing draws, it's a **stale render state** — the
  voxels exist in the data but aren't being drawn, usually after many rapid
  reloads of the *same* build. A `save_and_reload` redraws it.

**Script errors:**
- Check `get_console` for error messages after triggering a reload
- Common issue: syntax errors in `.nim` files show up in the console

**Position wrong:**
- The `origin` in JSON is world position; voxel coords in `edits` are LOCAL to origin
- Use `set_position` to fly the bot near the expected location and screenshot

**Hot-reload not triggering:**
- Always `touch` files after writing — don't rely on write time alone
- If still not working: `eval("load_level(\"" & level_name() & "\")")`

## level.json

Enu manages `level.json` itself — load order and level settings
(e.g. `show_prototypes`). Don't edit it by hand while Enu is running;
the next save overwrites it. To change a setting like
`show_prototypes`, edit the file while Enu is down.

## Screenshot Positions for Common Views

| View | x | y | z | rotation |
|------|---|---|---|----------|
| Overview (north-facing) | 0 | 25 | 20 | 180 |
| Ground level (player POV) | 0 | 2 | 5 | 180 |
| Side view (east) | -40 | 10 | -30 | 90 |
| Top-down | 0 | 50 | -30 | 0 |

`screenshot_at(x, y, z, distance, height, angle)` is usually nicer —
the bot smoothly flies to a vantage that frames the target world
position, no math needed.

`screenshot_from_player()` captures from the human's first-person
camera (no UI). `screenshot_from_player(with_ui=true)` includes
toolbar/console — useful when they're pointing at something on
screen.

## Working With the Human (Block Annotations)

The human can mark things in-world by placing or erasing blocks with
the in-game block tool, and the agent reads the log via
`get_block_log`. This is the lightest-weight way to point at specific
units/positions across a conversation.

Workflow:
1. **Human places markers**: chooses a color convention ("red = too
   big, blue = move me, eraser = delete") and clicks blocks onto the
   relevant units.
2. **Agent reads**: `get_block_log` returns one line per entry with
   `unit_id`, color, local position, and global position.
3. **Plan before acting**: read the log, summarize what each marker
   means, decide on changes, and confirm with the human if anything
   is ambiguous.
4. **Erase markers, then implement**: erase the markers first (so
   they don't get persisted to the unit's data files), then apply the
   actual change. Block edits are persistent — leaving them in means
   they survive reloads.
5. **`clear_block_log` when done**: empties the log for the next
   annotation session. (Also auto-cleared on `save_and_reload`.)

Markers on spawner instances move with the instance — if the agent
relocates a unit before erasing its marker, the eraser will end up at
the wrong local position. Always erase markers first, *then* edit
spawner positions.

To erase a block: from the player's eval, call
`place_block(Build(find_by_id("...")), vec3(x, y, z), eraser)` using
the `unit_id` and `local_position` from the log entry. The eraser
covers the placed block with an invisible MANUAL voxel.

## Detecting Voxel Overlaps (z-fighting)

Two builds whose voxels share a world position cause z-fighting —
flickering between the two colors as the camera moves. Hard to spot
in screenshots, obvious in motion.

```nim
# Via eval:
find_voxel_overlaps(limit = 100)
```

Returns one line per position with the unit IDs that share it. Skip
the spawner origins themselves (e.g. `build_market_spawner` at its
location) — those are markers, not voxels. Real overlaps are between
two `_proto_*_instance_*` clones, between a proto instance and a
root build, etc.

Scaled or rotated builds are skipped — their voxel-to-world mapping
isn't a simple translation and would report spurious results.
