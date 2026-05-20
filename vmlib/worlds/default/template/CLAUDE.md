# Enu Level — Claude Code Guide

This directory is an Enu level. You can create and modify it using file edits and
the MCP tools provided by the `enu` server.

## Quick Start

1. `get_level_dir` → confirm the level directory path
2. `screenshot` → see the current state
3. Edit or create scripts in `scripts/` and JSON in `data/`
4. Touch modified files, wait 5 seconds, `screenshot` again to verify

## MCP Tools Available

**Looking around:**
- `screenshot` — From the MCP bot's POV
- `screenshot_at(x, y, z, distance, height, angle)` — Smoothly move the bot to a vantage and frame a world position
- `screenshot_from_player(with_ui = false)` — From the human's first-person camera; `with_ui = true` includes toolbar/console overlay

**Querying:**
- `get_level_dir` — Absolute path to the current level directory
- `units_near(x, y, z, radius)` — Sorted nearest-first list of units within an xz-radius
- `get_block_log` — Recent blocks the human placed (or erased) in-game; used for annotation (see "Working With the Human" below)
- `get_console` — Recent Enu console output (use after `eval` to see `echo` results)

**Mutating:**
- `eval(code, top_level = false, unit_id = "")` — Run Nim code in the Enu scripting context.
  - Default: runs as an expression inside the player's module, returns the value
  - `top_level = true`: runs as module-level code (allows `import`, top-level `proc`/`type`); no return value
  - `unit_id = "..."`: runs in that unit's module instead of the player. Spawner clones (`*_proto_*_instance_*`) can't be targeted; use their proto or another root unit
- `move_unit(id, x, y, z)` — Move a unit and persist the new spawn position across reload
- `delete_unit(id)` — Remove a unit and delete its on-disk script + data directory
- `set_position(x, y, z, rotation, id)` — Smoothly move a unit (default: the MCP bot) for a better view
- `clear_block_log` — Empty the block log for a fresh annotation session

## Coordinate System

```
      -Z = north / forward (player default facing direction)
      +Z = south / back (behind player spawn — avoid cluttering here)
      +X = east
      -X = west
       Y = height (0 = ground level)
```

Player spawns near origin (0, 0, 0) facing north (-Z). Build northward.

## Available Colors

`BLACK`, `BROWN`, `RED`, `GREEN`, `BLUE`, `WHITE`

In scripts: `black`, `brown`, `red`, `green`, `blue`, `white` (lowercase enum values)

## Level File Structure

```
<level-dir>/
  level.json          — load order for scripted objects (auto-managed)
  data/
    <id>/
      <id>.json       — voxel data (position + block edits)
  scripts/
    <id>.nim          — optional Nim script for a build or bot
```

Bot IDs start with `bot_`, build IDs with `build_`.

## Voxel Data Format (`data/<id>/<id>.json`)

```json
{
  "id": "build_name",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [world_x, world_y, world_z]
  },
  "start_color": "BROWN",
  "edits": {
    "build_name": [
      [[local_x, local_y, local_z], [1, "COLOR"]],
      [[local_x, local_y, local_z], [0, ""]]
    ]
  }
}
```

- `origin` = world position of the build object
- Edit coordinates are **local** to the origin
- `[1, "COLOR"]` = place voxel; `[0, ""]` = erase voxel
- `start_color` sets the default color (used by scripted builds)
- For scripted builds/bots with no static voxels, use `"edits": {"build_name": []}`

## Creating a Static Build (JSON only)

1. Create `data/<name>/` directory
2. Write `data/<name>/<name>.json` with voxel edits
3. **No entry in `level.json`** — static builds load automatically

## Creating a Scripted Build or Bot

1. Create `data/<name>/<name>.json` — sets position and `start_color`
2. Create `scripts/<name>.nim` — the Nim script
3. Touch both files — Enu auto-detects and loads them (`level.json` is auto-managed)

## Hot-Reload

Enu watches JSON files for changes every ~2 seconds. After editing:

1. Write all files
2. `touch` them to ensure a newer mtime
3. Wait 4–5 seconds, then take a screenshot to verify

For a guaranteed full reload (also picks up vmlib/API changes):
```nim
press_action("save_and_reload")
```

## Working With the Human (Block Annotations)

The human can mark units in-world by placing or erasing blocks with the
in-game block tool. `get_block_log` returns the recent placements (per
local player), each entry with `unit_id`, color, local position, and
global position. This is the lightest-weight way to point at specific
things across a conversation.

Workflow when the human gives instructions referencing colored blocks:

1. `get_block_log` — read what they marked
2. **Plan** — summarize each marker, decide on changes, confirm
   anything ambiguous before acting
3. **Erase the markers first** — block edits are persistent and will
   stick to the unit's data files otherwise. Erasing first also avoids
   losing track of which local position belonged to which marker if the
   underlying unit moves
4. **Implement** — apply the actual changes
5. `clear_block_log` — empty the log for the next session
   (also auto-cleared on `save_and_reload`)

To erase a marker from the player's eval:
```nim
place_block(Build(find_by_id("build_some_id")), vec3(x, y, z), eraser)
```
using the `unit_id` and `local_position` from the log entry.

See `/reload-verify` for the long version and for `find_voxel_overlaps`,
which detects actual voxel-level z-fighting between two builds.

---

## Build Scripts (procedural drawing)

```nim
speed = 0          # build instantly (default for scripted builds)
color = brown      # set draw color
drawing = true     # enable voxel placement (true by default for builds)

# Movement (draws voxels while moving)
forward 10         # draw 10 voxels forward
right 5
up 3
turn right         # turn 90 degrees right
turn left
turn 45.0          # turn by degrees
lean back, 30      # tilt 30 degrees

# Loops
5.times:
  forward 3
  turn right

10.times(i):       # with index
  forward i.float
  up 1

# Randomness
color = random(red, green, blue)
forward 3 .. 8        # random int in range
turn -30.0 .. 30.0    # random float in range
if 1 in 3:            # 1-in-3 chance
  color = white

# Save and restore position/orientation
save()
restore()
```

## Block Placement Helpers

Use these inside build scripts for direct coordinate-based placement:

```nim
# Place a single block at local integer coords
place(x, y, z, color)

# Fill a box region
fill_box(x1, y1, z1, x2, y2, z2, color)

# Fill a sphere (radius in blocks, float)
fill_sphere(cx, cy, cz, radius, color)

# Fill a vertical cylinder
fill_cylinder(cx, y1, y2, cz, radius, color)

# Examples:
fill_box(0, 0, 0, 9, 0, 9, brown)         # 10×10 floor
fill_box(0, 0, 0, 9, 5, 0, brown)         # 10×6 wall
fill_sphere(5, 5, 5, 4.0, green)          # sphere canopy
fill_cylinder(5, 0, 8, 5, 3.0, brown)    # round tower
fill_box(2, 1, 2, 7, 1, 7, black)        # hollow out a floor area
```

After drawing, switch to move mode to animate or reposition:
```nim
move me
speed = 5
forward 10    # moves the build object, doesn't draw
```

## Named Prototypes (reusable builds)

Use `CamelCase` for prototype names. Lowercased/snake_case names work but
the convention is `name Tower`, `name WallSegment`, etc. — distinguishes
type names from regular identifiers.

Origin tip: every Build starts with a default block at local `(0, 0, 0)`
(it's how the in-game block tool creates the build). If your prototype's
voxels don't cover that voxel, it'll show through as a stray block. Either
draw over `(0, 0, 0)` or set spawner positions to `vec3(x, 1, z)` so the
default block lands above the ground floor.

```nim
# Define a reusable prototype in a build script:
name Tower(height = 10, color = brown)
speed = 0

# Skip the prototype definition itself (only draw for instances):
if not is_instance:
  show = false
  quit()

color = color
height.times:
  fill_box(0, 0, 0, 3, 0, 3, color)
  up 1

# Instantiate from any other script. Bump y by 1 so the default block
# at local (0, 0, 0) sits above the floor instead of in it:
Tower.new(height = 20, color = red, position = vec3(0, 1, 0))
Tower.new(height = 15, color = blue, position = vec3(20, 1, -10))
```

## Animated Builds (state machine)

```nim
name Door(open = false, width = 20, height = 11)
speed = 0
# Drawing phase:
height.times:
  right width
  turn 180
  up 1

move me     # switch to move mode (sets `home` to current position)
speed = 5

loop:
  nil -> sleep as door_closed
  if open:
    door_closed -> left(home + width) as door_open
  else:
    door_open -> right(home) as door_closed
```

---

## Bot Scripts

```nim
color = green
speed = 3


forward 10
turn right
turn player    # face the player
turn 45.0
```

### Say / Signs

```nim
# Simple speech bubble:
say "Hello!"

# Bubble + rich text sign (markdown in the second string):
say "Hello!", """
  # Greetings

  I am a friendly bot.

  - [Do something](<nim://some_proc()>)
  - [Next Level](<nim://press_action("next_level")>)
"""

# Control sign size:
say overview, details, height = 2, width = 6, size = 610

# Cycle through multiple messages on repeated calls:
let messages = ["First time!", "Second time!", "Still here."]
say cycle(messages)
```

### State Machine

```nim
# State procs must be defined BEFORE the loop:
-wander:
  forward 3 .. 8
  turn -45.0 .. 45.0

-chase:
  turn player
  forward 5

-caught:
  say "Got you!"
  sleep 2

loop:
  nil -> wander                  # start state
  if player.near(10):
    wander -> chase              # conditional transition (use if, not inline)
  if player.near(3):
    chase -> caught
  caught -> wander               # unconditional (always)
```

State transitions support callbacks and renaming:
```nim
if start_position.far(20):
  wander -> go_home as wander_home
(wander, wander_home) ==> chase do:
  say "I see you!"
```

### Sensing and Position

```nim
# Distance checks
if player.near(5): say "You're close!"
if player.far(20): turn player

# Exact distance/angle
let d = distance(player)
let a = angle_to(player)

# Position math
let home = position    # save current position
position = home + vec3(5, 0, 0)   # move east 5 units
```

### Iterating Units

```nim
for b in Bot.all:
  echo b.id

# Find a specific bot created after a point in time:
let before = frame_created
some_action()
for b in Bot.all:
  if b.frame_created > before:
    echo "new bot: ", b.id
```

---

## Scripting Utilities

```nim
# Console output (read with get_console MCP tool)
echo "position: ", position
echo "level: ", level_name()

# Timing
sleep 1.0
let t = now()
# ...do stuff...
echo "elapsed: ", now() - t

# Nim standard library is available:
import math
let angle = sin(0.5) * 180.0 / PI
```

## Eval Tips

`eval` runs Nim code globally (not inside any unit):

```nim
# Check a unit's position:
echo Player.first.position        # → see with get_console
echo Bot.all.len
echo level_name()

# Trigger a reload:
load_level("level-name")
press_action("save_and_reload")
```

Cannot be used to directly create builds or call unit-specific procs like `forward`.
