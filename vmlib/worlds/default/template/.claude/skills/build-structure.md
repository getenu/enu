# Build a Static Structure

Create a voxel structure using a Nim build script. The shape primitives
(`box`, `sphere`, `cylinder`, `wall`, `floor`) draw at the turtle's
current transform by default and accept an explicit `at = vec3(...)`
when you want absolute coords. For shapes that flow naturally as
turtle movement (spirals, towers, mazes), use the turtle commands
directly.

## Usage

```
/build-structure <description>
```

## Quick Start

A scripted build needs two files:

**`data/<name>/<name>.json`** — world position:
```json
{
  "id": "build_my_wall",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [0.0, 0.0, -20.0]
  },
  "start_color": "BROWN",
  "edits": {}
}
```

**`scripts/<name>.nim`** — Nim script that builds the shape:
```nim
speed = 0
box(width = 10, height = 8, depth = 1, color = brown)  # 10-wide × 8-tall wall in front of the turtle
```

Then add `"build_my_wall"` to the `load_order` array in `level.json`.

## API Reference

All shape primitives default to the turtle's current transform.
Pass `at = vec3(...)` to override with an explicit local coord.

```nim
# At the turtle (extends along turtle's right / up / forward):
box(width = W, height = H, depth = D, color = c)
sphere(size = D, color = c)            # D = diameter, not radius
cylinder(size = D, height = H, color = c)

# At explicit coords (axis-aligned, optionally yaw-rotated):
box(width = W, height = H, depth = D, at = vec3(x, y, z), color = c)
box(width = W, height = H, depth = D, at = vec3(x, y, z),
    color = c, rotation = 45)
box(at = vec3(x1, y1, z1), to = vec3(x2, y2, z2), color = c)  # corner-to-corner
sphere(size = D, at = vec3(x, y, z), color = c)
cylinder(size = D, height = H, at = vec3(x, y, z), color = c)

# Walls and floors are thin wrappers over `box` that extend along the
# turtle's forward and leave the turtle at the far end so calls chain:
wall(length = N, height = H, color = c)
floor(length = N, width = W, color = c)

# Single block (always at integer local coords):
place(x, y, z, color)
```

`box` defaults to the back-bottom-left corner sitting at the turtle —
`box(width = 1, height = 1, depth = 5)` covers the same voxels as
`forward 5; back 5`. Pass `pivot = centre` or `pivot = bottom_centre`
for the other useful pivots (sphere/cylinder default to centre /
bottom-centre respectively).

`fill = false` makes shapes hollow (1-voxel shell). `eraser` color
removes voxels.

Colors: `black`, `brown`, `red`, `green`, `blue`, `white`, `eraser`

## Common Structure Patterns

### Flat floor / platform
```nim
speed = 0
box(width = 10, height = 1, depth = 10, color = brown)
```

### Solid wall
```nim
speed = 0
box(width = 10, height = 8, depth = 1, color = brown)
```

### Hollow box (room)
```nim
speed = 0
box(width = w, height = h, depth = d, color = brown)  # solid shell
# Hollow out the interior with eraser inset by 1 on each side:
box(width = w - 2, height = h - 2, depth = d - 2,
    at = position + vec3(1, 1, -(d - 2)), color = eraser)
```

### Arch (wall with opening)
```nim
speed = 0
let w = 13
let h = 10
let arch_w = 5
let arch_h = 7
let side = (w - arch_w) div 2

# Left pillar
box(width = side, height = h, depth = 1, color = brown)
right side + arch_w
# Right pillar
box(width = side, height = h, depth = 1, color = brown)
left arch_w
up arch_h
# Lintel above the opening
box(width = arch_w, height = h - arch_h, depth = 1, color = brown)
```

### Stepped pyramid
```nim
speed = 0
let base = 24
let tiers = 5
let tier_height = 3

for tier in 0 ..< tiers:
  let offset = tier * 2
  let size = base - offset * 2
  box(
    width = size, height = tier_height, depth = size,
    at = vec3(offset.float, (tier * tier_height).float, -(offset + size - 1).float),
    color = brown,
  )
```

### Tree
```nim
speed = 0
let trunk_h = 6
cylinder(size = 1, height = trunk_h, color = brown)  # trunk at turtle
up trunk_h + 2
sphere(size = 6, color = green)                       # canopy above
```

### Column row
```nim
speed = 0
let count = 5
let spacing = 4
let col_h = 8

count.times:
  cylinder(size = 1, height = col_h, color = brown)
  up col_h
  sphere(size = 3, color = brown)                     # capital
  down col_h
  right spacing
```

### Tower (hollow cylinder shell)
```nim
speed = 0
cylinder(size = 8, height = 20, color = brown, fill = false)
```

### Bridge / walkway
```nim
speed = 0
let length = 30
let width = 3

# Deck
box(width = width, height = 1, depth = length, color = brown)
# Railings (1 voxel thick along each long edge)
box(width = 1, height = 3,
    at = position + vec3(0, 1, 0), depth = length, color = brown)
box(width = 1, height = 3,
    at = position + vec3((width - 1).float, 1, 0), depth = length, color = brown)
```

## Mixing shapes with turtle movement

Turtle commands (`forward`, `right`, `up`, `turn`, `lean`) compose
with the shape primitives — every shape uses the turtle's current
position and heading as its anchor, so walking + drawing builds
naturally:

```nim
speed = 0
import math

# Spiral tower: drop a small cylinder, step up and rotate, repeat
color = brown
100.times:
  cylinder(size = 2, height = 1, color = brown)
  up 1
  turn 10.0
  forward 1
```

For shapes that need to rasterise at the turtle's full orientation
(staircases, tilted slabs), use `wall` / `floor` — they go through
`box` at the turtle's transform, which respects `lean` and `turn`:

```nim
# Staircase: each iteration draws a tread, leans 90° to draw the
# riser as a tilted floor, leans back.
10.times:
  floor 3, width = 5, color = brown   # horizontal tread
  lean back
  floor 3, width = 5, color = brown   # vertical riser
  lean forward
```

## Full Workflow

1. Get level dir: `get_level_dir`
2. Write `data/<name>/<name>.json` (position JSON with `"edits": {}`)
3. Write `scripts/<name>.nim` using the shape primitives
4. Add name to `level.json` load_order
5. Touch the files, wait 4–5 seconds, screenshot to verify

## Furniture Inside a Structure

For anything bigger than a single placement (bedroom, kitchen, dining area),
**don't try to render furniture with 1:1-voxel `place` calls.** A 1 m³ cube
doesn't read as a chair; three cubes in a row don't read as a couch. Build
furniture as scaled prototypes (see `/build-script` for the `name X(...)`
prototype mechanism), then instantiate them from the room's script.

1:1 voxels *are* fine for things that really are box-shaped at human scale:
counters, fridges, dressers, signs, wall-mounted TVs. Everything else gets
a proto.

Example proto sizes that have worked (illustrative — design your own per
build; these are starting points, not a fixed catalog):

| Proto (example) | Internal voxels | Scale | World footprint (m) |
|-----------------|-----------------|-------|----------------------|
| `BedQueen` | 8 × 5 × 12 | 0.25 | 2 × 1.25 × 3 |
| `BedTwin` | 6 × 5 × 10 | 0.25 | 1.5 × 1.25 × 2.5 |
| `Sofa` | 12 × 5 × 5 | 0.25 | 3 × 1.25 × 1.25 |
| `DiningTable` | 8 × 3 × 5 | 0.25 | 2 × 0.75 × 1.25 |
| `DiningChair` | 2 × 5 × 2 | 0.25 | 0.5 × 1.25 × 0.5 |
| `Toilet` | 4 × 6 × 4 | 0.25 | 1 × 1.5 × 1 |
| `Bathtub` | 8 × 3 × 5 | 0.25 | 2 × 0.75 × 1.25 |

By default `position` places the proto's local `(0, 0, 0)`. For protos
that need to be rotated around a table or otherwise placed at arbitrary
angles, add an `anchor:` block to declare a different pivot (typically
the centre). See `/build-script` for the recipe.

For a `CoffeeTable`, `Lamp`, `Bookshelf`, `Workbench`, etc. — write a new
proto in the same pattern. See `/build-plan` for the 1 m clearance rule and
the scaled-instance placement formula, and `/build-script` for the
`anchor:` block.

## Multi-Room Buildings (rooms, halls, doors)

A few patterns that keep multi-room interiors clean:

### Door openings

Place doors by erasing voxels in a wall, 2 wide × 3 tall:

```nim
# Front door in south wall: erase a 2×3 hole at the wall's z plane.
box(width = 2, height = 3, depth = 1,
    at = vec3(8, 1, 16), color = eraser)
```

### Hallway depth

A 1-voxel-deep hallway feels claustrophobic (you scrape both walls when you
walk through). Go 2 voxels deep:

```nim
# Hallway between back rooms (z=6 divider) and front rooms (z=9 divider)
# leaves z=7..8 as a 2-deep walkway.
box(width = 18, height = 4, depth = 1,
    at = vec3(0, 1, 6), color = white)
box(width = 18, height = 4, depth = 1,
    at = vec3(0, 1, 9), color = white)
```

### Windows as holes, not blue blocks

`box(..., color = blue)` for windows reads as a "blue panel," not a
window. Use `eraser` to punch real holes instead:

```nim
box(width = 3, height = 2, depth = 1,
    at = vec3(2, 2, 0), color = eraser)   # 3-wide × 2-tall window
```

### Optional roof toggle for verification

A `const ROOF_OFF` at the top of the script lets you re-load the level with
the roof omitted so top-down screenshots show the interior layout:

```nim
const ROOF_OFF = false  # flip to true for layout-verification screenshots

# ... later ...
when not ROOF_OFF:
  box(width = 20, height = 1, depth = 18,
      at = vec3(-1, 5, 0), color = brown)   # eave
  box(width = 14, height = 1, depth = 12,
      at = vec3(2, 6, -2), color = brown)   # ridge step
```

Touch the script file after flipping `ROOF_OFF` — the hot-reload
re-runs the build script from a clean voxel state, so the toggle
takes effect without `save_and_reload`.
