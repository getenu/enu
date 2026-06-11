# Enu Level — Claude Code Guide

This directory is an Enu level. Create and modify it with file edits and
the MCP tools provided by the `enu` server.

## Where to look

- **`/build-plan`** — plan multi-unit builds before laying voxels
- **`/build-structure`** — shape primitives, structural patterns, furniture
- **`/build-script`** — turtle drawing, prototypes, anchors, animation
- **`/add-bot`** — bots and behavior state machines
- **`/game-mechanics`** — collectibles, triggers, doors, win conditions
- **`/sign-menu`** — signs, menus, markdown panels
- **`/reload-verify`** — the edit/verify loop in depth, block annotations
- **`.claude/examples/`** — verified, working scripts for towers, castles,
  trees, skyscrapers, doors, furniture, bots, and more. See its README
  index. **Prefer copying an example over writing from scratch.**

## Quick Start

1. `get_level_dir` → confirm the level directory path
2. `screenshot` → see the current state
3. Edit or create scripts in `scripts/` and JSON in `data/`
4. `wait_for_script(unit_id)` → loads/reloads the unit and returns its
   bounds, or the script's error
5. Sanity-check the bounds, then `screenshot` to verify

## MCP Tools

Every screenshot/positioning tool takes an optional `agent_id`: pass a
short stable id (your name works) to get your own bot, with its own
color and position. Subagents each passing their own id drive a swarm
of distinctly-colored bots.

**Looking around:**
- `screenshot(agent_id)` — from your bot's POV
- `screenshot_at(x, y, z, distance, height, angle, agent_id)` — fly the bot to a vantage and frame a world position
- `screenshot_top_down(x, z, size, agent_id)` — orthographic map view centered on (x, z); `size` is the half-extent (default 30 → 60×60 area). Use for layout planning.
- `screenshot_from_player(with_ui = false)` — from the human's first-person camera; `with_ui = true` includes the toolbar/console overlay

**The edit loop:**
- `wait_for_script(unit_id, timeout = 30)` — reload the unit if its files changed, block until the script finishes *and its voxels are fully rendered*. Success returns the unit's world bounds (`bounds: (min) .. (max)`) — check them against the intended footprint (a 1×1×1 box means the script drew nothing). Failure returns the script's error with file:line, or "still rendering" if the voxel pipeline can't drain within the timeout. **Animated builds (`loop:` / `move me`) never finish** — "still running" after the timeout means alive, not stuck; use a short timeout and verify those with bounds or a screenshot.
- `get_console` — console output (`echo` from eval lands here)
- `clear_console` — empty the console; clear before a run you want clean error signal from

**Querying:**
- `get_level_dir` — absolute path to the current level directory
- `units_near(x, y, z, radius)` — sorted nearest-first unit list within an xz-radius; includes spawner clones
- `get_block_log` — recent blocks the human placed/erased in-game (annotation workflow — see `/reload-verify`)
- `eval(code, top_level = false, unit_id = "")` — run Nim in the Enu scripting context. Default returns the expression's value from the player's module; `top_level = true` allows `import`/`proc` (no return value); `unit_id` targets a unit's module (spawner clones can't be targeted — use their proto or another root unit).

**Spatial queries** (via `eval`):
- `units_in_box(x1, y1, z1, x2, y2, z2)` — `seq[Unit]` whose origins are inside the box. To enumerate units by kind/id, loop `Build.all` / `Bot.all` instead (see `/reload-verify`).
- `floor_at(x, z)` — top y with a visible voxel, or -1
- `clear_box(...)` — true if no voxels in the box
- `find_voxel_overlaps(limit)` — positions where two builds share a voxel (z-fighting)
- `unit.bounds` — tight world-space AABB after scale/rotation/anchor
- `Proto.bounds_at(position, rotation, scale)` — predicted AABB of a hypothetical instance, for pre-placement clearance checks
- `a.overlaps(b)`, `units_overlapping(box)`, `box_is_free(box)` — bounds-vs-bounds checks
- `WorldBox` helpers: `b.size`, `b.centre`, `p in b`, `a.intersects(b)`, `b.expanded(margin)`

**Mutating:**
- `move_unit(id, x, y, z)` — move a unit and persist the new spawn position
- `delete_unit(id)` — remove a unit and delete its on-disk files (cannot be undone)
- `set_position(x, y, z, rotation, id, agent_id)` — glide a unit (default: your bot)
- `clear_block_log` — empty the block log

## World Rules

```
      -Z = north / forward (player default facing direction)
      +Z = south / back
      +X = east, -X = west
       Y = height (0 = ground surface)
```

- Player spawns at (0, 0, 0) facing north (-Z). **Keep ≥ 5 m around the
  spawn clear.**
- The ground is a 1000×1000 plane centred on the origin: solid floor
  from x/z = **-500 to +500**. Keep every build's full footprint inside,
  with a margin.
- Place origins at **y = 0** so the lowest voxel rests on the ground.
- Draw distance is 256 m.
- Colors: `black`, `brown`, `red`, `green`, `blue`, `white` (+ `eraser`
  to remove voxels). `SCREAMING_CASE` in JSON (`"BROWN"`).

## Level Files

```
<level-dir>/
  level.json          — managed by Enu (load order, settings); don't edit
                        by hand while Enu is running. Settings (e.g.
                        "show_prototypes") are changed by editing it
                        while Enu is down.
  data/<id>/<id>.json — unit position (+ hand-placed block edits)
  scripts/<id>.nim    — the unit's script
```

Build ids start with `build_`, bot ids with `bot_`. A script declaring
`name FlyerShip` gets the id `build_flyer_ship` (`build_` + snake_case
of the name) and Enu renames its files to match — name the files that
way from the start so `wait_for_script` ids line up.

**`data/<id>/<id>.json`:**

```json
{
  "id": "build_name",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [world_x, 0.0, world_z]
  },
  "start_color": "BROWN",
  "edits": {}
}
```

To create a unit: write both files and touch them — Enu picks them up
(then `wait_for_script` to confirm). Static builds can be JSON-only,
with voxel `edits` entries of the form
`[[local_x, local_y, local_z], [1, "COLOR"]]` (`[0, ""]` erases).

## Hot-Reload

Enu watches script + JSON files (~2 s poll). `wait_for_script(unit_id)`
triggers the rescan and blocks until the script ran. A reload is a full
re-run from a clean voxel state, so edits that remove geometry produce
a clean rebuild; hand-placed JSON `edits` are preserved.

When a prototype script changes, scripts that reference it keep their
previously compiled types until they reload — touch dependents in
dependency order (proto → referencing protos → spawners).

`press_action("save_and_reload")` reloads the entire level and is
disruptive to anyone else in the world — reserve it for vmlib/engine
changes or a broken `level.json`.

## Script Crash-Course

Builds draw instantly by default; set `speed = 1`+ only to watch the
drawing happen. Full reference: `/build-script` and `/build-structure`.

```nim
color = brown
forward 10            # turtle-draw 10 voxels
turn right            # 90°; turn 45.0 for degrees
lean back, 30         # pitch; lean left/right = roll
up 3

place(x, y, z, color)                                  # single voxel
box(width = W, height = H, depth = D, color = c)       # at the turtle
box(vec3(x1, y1, z1), vec3(x2, y2, z2), color = c)     # corner-to-corner
sphere(size = D, at = vec3(x, y, z), color = c)        # D = diameter
cylinder(size = D, height = H, at = vec3(x, y, z), color = c)
wall(length = N, height = H, color = c)                # chains forward
floor(length = N, width = W, color = c)

5.times: ...          # loops; 10.times(i): ... with index
forward 3 .. 8        # random int in range
if 1 in 3: ...        # 1-in-3 chance
color = cycle(red, white)  # alternates per call
save()                # save turtle pose + color
restore()
```

`size` accepts ints or floats; rasterisation is voxel-centred, so
effective widths are odd (`size = 4` and `5` both span 5 voxels) and
fractional sizes make smooth tapers. Avoid naming locals/proc params
`height`/`width`/`radius`/`size`/`color` (unit accessors) or `home`
(a built-in position offset).

**Prototypes:** `name Tower(height = 10)` makes a reusable proto;
instantiate from a *different* script with
`Tower.new(height = 20, position = vec3(0, 0, -10), color = red)`.
Never call `X.new` in the script that declares `name X` — it recurses
and crashes Enu. Capture params into locals before drawing, don't
declare a `color` param (pass color to `.new()` — its default is
eraser, which draws invisibly), and cover local `(0, 0, 0)` (every
build starts with a default block there). `/build-script` has the full
trap list, `anchor:` blocks for rotation pivots, and animation
(`move me` + `loop:` state machines).

**Bots** use the same state-machine system with `say`, `turn player`,
`player.near(N)` — see `/add-bot` and `.claude/examples/bot_greeter.nim`.

## Working With the Human (Block Annotations)

The human marks units by placing colored blocks in-game;
`get_block_log` returns each placement with `unit_id`, color, and
local/global positions. Read the log, plan, **erase the markers first**
(they persist into the unit's data otherwise), implement, then
`clear_block_log`. Full workflow + marker-erasing recipe:
`/reload-verify`.
