# Enu Level — Claude Code Guide

This directory is an Enu level. You can create and modify it using file edits and
the MCP tools provided by the `enu` server.

## MCP Tools Available

- `screenshot` — Take a screenshot from the MCP bot's POV. Optional `unit_id` for another unit's view; optional `pitch` in degrees (e.g. `-90` for top-down, `-30` for angled down)
- `eval` — Run Nim code in the Enu scripting context. Output goes to `get_console`, not returned directly.
- `get_console` — Get recent Enu console output (use after `eval` to see results)
- `get_level_dir` — Returns the absolute path to the current level directory (this directory)
- `set_position` — Move the MCP bot (or any unit by id) to a position for a better view

## Coordinate System

```
      -Z = north / forward (player default facing direction)
      +Z = south / back (behind player spawn — avoid cluttering here)
      +X = east
      -X = west
       Y = height (0 = ground level)
```

Player spawns near origin (0, 0, 0) facing north (-Z). Build your world extending northward.

## Available Colors

`BLACK`, `BROWN`, `RED`, `GREEN`, `BLUE`, `WHITE`

In scripts: `black`, `brown`, `red`, `green`, `blue`, `white` (lowercase enum values)

## Level File Structure

```
<level-dir>/
  level.json          — load order for scripted objects (auto-managed)
  data/
    <build_id>/
      <build_id>.json — voxel data (position + block edits)
  scripts/
    <build_id>.nim    — optional Nim script for a build or bot
```

## Voxel Data Format (data/<id>/<id>.json)

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

## Creating a Static Build (JSON only)

1. Create `data/<name>/` directory
2. Write `data/<name>/<name>.json` with voxel edits
3. **No entry needed in level.json** — static builds load automatically from data/

## Creating a Scripted Build (Nim script)

1. Create `data/<name>/<name>.json` — sets position and start_color
2. Create `scripts/<name>.nim` — Nim script that procedurally builds
3. Add `<name>` to `level.json`'s load order array

## Hot-Reload Pattern

Enu watches JSON files for changes every ~2 seconds. After editing:

1. Write all files
2. `touch` them to ensure a newer mtime
3. Wait 4–5 seconds
4. Take a screenshot to verify

For a guaranteed full reload (also reloads vmlib/API changes):
```nim
press_action("save_and_reload")
```

## Scripting Quick Reference

### Build scripts (procedural voxel drawing)

```nim
speed = 0          # build instantly
color = red        # set draw color
drawing = true     # enable voxel placement (default true for builds)

# Movement (draws voxels while moving)
forward 10         # draw 10 voxels forward
right 5            # draw 5 voxels right
up 3               # draw 3 voxels up
turn right         # turn 90 degrees right
turn left          # turn 90 degrees left
turn 45.0          # turn by degrees
lean back, 30      # tilt forward 30 degrees

# Loops
5.times:           # repeat 5 times
  forward 3
  turn right
10.times(i):       # with index variable
  forward i.float

# Random values
color = random(red, green, blue)
forward 3 .. 8     # random int in range
turn -30.0 .. 30.0 # random float in range
if 1 in 3:         # 1-in-3 chance
  color = white

# Save/restore position
save()             # save current position and orientation
restore()          # restore saved position

# Switch to move mode (after building)
move me
speed = 5
forward 10         # moves the build object, doesn't draw
```

### Bot scripts (navigation and behavior)

```nim
color = green
speed = 3

forward 10         # walk forward
turn right         # turn
turn player        # face the player
say "Hello!"       # show speech bubble
say "Short text", "# Full markdown sign\n\nMore details..."

# State machine
loop:
  nil -> wander
  wander -> chase if player.near(10)
  chase -> caught if player.near(3)

-wander:
  forward 3 .. 8
  turn -45 .. 45

-chase:
  turn player
  forward 5

-caught:
  say "Got you!"
  sleep 2
```

### Named prototypes (reusable builds)

```nim
# In the build's script:
name tower(height = 10, sides = 4)
speed = 0
height.times:
  sides.times:
    forward 10
    turn 360 / sides
  up 1

# In another script, create instances:
tower.new(height = 20, sides = 6, color = blue)
```

### Animated builds (state machine)

```nim
name Door(open = false, width = 20, height = 11)
speed = 0
height.times:
  right width
  turn 180
  up 1

move me
speed = 5

loop:
  nil -> sleep as door_closed
  if open:
    door_closed -> left(home + width) as door_open
  else:
    door_open -> right(home) as door_closed
```

### Block placement helpers (use inside build scripts)

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
fill_box(0, 0, 0, 9, 7, 0, brown)        # 10×8 wall
fill_box(0, 0, 0, 9, 0, 9, brown)        # 10×10 floor
fill_sphere(5, 5, 5, 4.0, green)         # sphere canopy
fill_cylinder(5, 0, 8, 5, 3.0, brown)   # round tower
```

## Python Voxel Generator (alternative)

Use Python to generate complex structures as JSON:

```python
import json, os

LEVEL_DIR = "<level_dir>"  # from get_level_dir MCP tool

def write_build(name, origin, edits, color="BROWN"):
    data = {
        "id": name,
        "start_transform": {
            "basis": [[1.0,0.0,0.0],[0.0,1.0,0.0],[0.0,0.0,1.0]],
            "origin": [float(origin[0]), float(origin[1]), float(origin[2])]
        },
        "start_color": color,
        "edits": {name: edits}
    }
    path = os.path.join(LEVEL_DIR, "data", name, name + ".json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f)

def vox(x, y, z, color="BROWN"):
    return [[float(x), float(y), float(z)], [1, color]]

def erase(x, y, z):
    return [[float(x), float(y), float(z)], [0, ""]]

# Example: 5x5x5 cube
edits = [vox(x, y, z) for x in range(5) for y in range(5) for z in range(5)]
write_build("build_my_cube", origin=(0, 0, -10), edits=edits, color="RED")
```

## Eval Tips

`eval` runs Nim code globally (not inside any unit). Useful for:
- Checking positions: `echo Player.first.position` → see with `get_console`
- Level info: `echo level_name()`
- Reloading: `load_level("level-name")`

Cannot be used to directly create builds (requires unit script context).
