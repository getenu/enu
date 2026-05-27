# Build a Static Structure

Create a voxel structure using a Nim build script. For complex arbitrary shapes
use `place`, `fill_box`, `fill_sphere`, and `fill_cylinder`. For shapes that
flow naturally as turtle movement (spirals, towers, mazes), use movement commands.

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
fill_box(0, 0, 0, 9, 7, 0, brown)  # 10-wide, 8-tall wall at z=0
```

Then add `"build_my_wall"` to the `load_order` array in `level.json`.

## API Reference

All placement functions work directly in build scripts (no `self` needed):

```nim
place(x, y, z, color)                        # single block
fill_box(x1, y1, z1, x2, y2, z2, color)      # filled box
fill_sphere(cx, cy, cz, radius, color)        # filled sphere
fill_cylinder(cx, y1, y2, cz, radius, color)  # vertical cylinder
```

Colors: `black`, `brown`, `red`, `green`, `blue`, `white`, `eraser`

Use `eraser` to hollow out previously placed blocks.

## Common Structure Patterns

### Flat floor / platform
```nim
speed = 0
fill_box(0, 0, 0, width-1, 0, depth-1, brown)
```

### Solid wall
```nim
speed = 0
fill_box(0, 0, 0, width-1, height-1, 0, brown)
```

### Hollow box (room)
```nim
speed = 0
fill_box(0, 0, 0, w-1, h-1, d-1, brown)       # solid
fill_box(1, 1, 1, w-2, h-2, d-2, eraser)       # hollow out interior
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
fill_box(0, 0, 0, side-1, h-1, 0, brown)
# Right pillar
fill_box(side + arch_w, 0, 0, w-1, h-1, 0, brown)
# Lintel (top bar above opening)
fill_box(side, arch_h, 0, side + arch_w - 1, h-1, 0, brown)
```

### Stepped pyramid
```nim
speed = 0
let base = 24
let tiers = 5
let tier_height = 3

for tier in 0 ..< tiers:
  let offset = tier * 2
  let size = base - offset * 2 - 1
  let y_start = tier * tier_height
  fill_box(offset, y_start, offset, offset + size, y_start + tier_height - 1, offset + size, brown)
```

### Tree
```nim
speed = 0
let trunk_h = 6
let cx = 2
let cz = 2

# Trunk
fill_cylinder(cx, 0, trunk_h - 1, cz, 0.6, brown)
# Canopy (sphere centered above trunk)
fill_sphere(cx, trunk_h + 2, cz, 3.2, green)
```

### Column row
```nim
speed = 0
let count = 5
let spacing = 4
let col_h = 8

for i in 0 ..< count:
  fill_box(i * spacing, 0, 0, i * spacing, col_h - 1, 0, brown)
  # cap
  fill_box(i * spacing - 1, col_h, -1, i * spacing + 1, col_h, 1, brown)
```

### Tower (round)
```nim
speed = 0
let height = 20
let radius = 4.0

for y in 0 ..< height:
  # Shell only (hollow cylinder)
  let r_outer = radius.ceil.int
  let r_inner = (radius - 1.5).ceil.int
  for x in -r_outer .. r_outer:
    for z in -r_outer .. r_outer:
      let d = sqrt((x*x + z*z).float)
      if d <= radius and d >= radius - 1.5:
        place(x + r_outer, y, z + r_outer, brown)
  # Floor every 6 blocks
  if y mod 6 == 0:
    fill_cylinder(r_outer, y, y, r_outer, radius, brown)
```

### Bridge / walkway
```nim
speed = 0
let length = 30
let width = 3

# Deck
fill_box(0, 0, 0, width-1, 0, length-1, brown)
# Railings
fill_box(0, 1, 0, 0, 3, length-1, brown)
fill_box(width-1, 1, 0, width-1, 3, length-1, brown)
```

## Mixing place/fill with Turtle Movement

For spiral or organic shapes, turtle movement is often cleaner:

```nim
speed = 0
import math

# Spiral tower using turtle
color = brown
100.times(i):
  forward 1
  turn 10.0
  up 0.5   # floats work for sub-block stepping
```

Then use `place`/`fill_box` for precision add-ons:
```nim
# Add a roof after the spiral
let top_y = 50
fill_box(-5, top_y, -5, 5, top_y, 5, brown)
```

## Full Workflow

1. Get level dir: `get_level_dir`
2. Write `data/<name>/<name>.json` (position JSON with `"edits": {}`)
3. Write `scripts/<name>.nim` using `fill_box`, `place`, etc.
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

| Proto (example) | Internal voxels | Scale | World footprint (m) | Origin |
|-----------------|-----------------|-------|----------------------|--------|
| `BedQueen` | 8 × 5 × 12 | 0.25 | 2 × 1.25 × 3 | NW corner |
| `BedTwin` | 6 × 5 × 10 | 0.25 | 1.5 × 1.25 × 2.5 | NW corner |
| `Sofa` | 12 × 5 × 5 | 0.25 | 3 × 1.25 × 1.25 | NW corner |
| `DiningTable` | 8 × 3 × 5 | 0.25 | 2 × 0.75 × 1.25 | NW corner |
| `DiningChair` | 2 × 5 × 2 | 0.25 | 0.5 × 1.25 × 0.5 | **centred** |
| `Toilet` | 4 × 6 × 4 | 0.25 | 1 × 1.5 × 1 | NW corner |
| `Bathtub` | 8 × 3 × 5 | 0.25 | 2 × 0.75 × 1.25 | NW corner |

The "Origin" column distinguishes protos whose `position` is the
NW-bottom corner of the displayed object (the natural pattern with
`fill_box(0, 0, 0, ...)`) from protos drawn around their origin with
negative voxel coords (rotation-friendly). Anything that gets rotated
around a table or otherwise placed at arbitrary angles wants the
centred-origin pattern — see `/build-script` for the recipe.

For a `CoffeeTable`, `Lamp`, `Bookshelf`, `Workbench`, etc. — write a new
proto in the same pattern. See `/build-plan` for the 1 m clearance rule and
the scaled-instance placement formula, and `/build-script` for the
rotation pattern.

## Multi-Room Buildings (rooms, halls, doors)

A few patterns that keep multi-room interiors clean:

### Door openings

Place doors by erasing voxels in a wall, 2 wide × 3 tall:

```nim
# Front door in south wall at z=16, centered at x=8..9
fill_box(8, 1, 16, 9, 3, 16, eraser)
```

### Hallway depth

A 1-voxel-deep hallway feels claustrophobic (you scrape both walls when you
walk through). Go 2 voxels deep:

```nim
# Hallway between back rooms (z=6 divider) and front rooms (z=9 divider)
# leaves z=7..8 as a 2-deep walkway.
fill_box(0, 1, 6, 17, 4, 6, white)
fill_box(0, 1, 9, 17, 4, 9, white)
```

### Windows as holes, not blue blocks

`fill_box(..., blue)` for windows reads as a "blue panel," not a window.
Use `eraser` to punch real holes instead:

```nim
fill_box(2, 2, 0, 4, 3, 0, eraser)  # 3-wide × 2-tall window in north wall
```

### Optional roof toggle for verification

A `const ROOF_OFF` at the top of the script lets you re-load the level with
the roof omitted so top-down screenshots show the interior layout:

```nim
const ROOF_OFF = false  # flip to true for layout-verification screenshots

# ... later ...
when not ROOF_OFF:
  fill_box(-1, 5, -1, 18, 5, 16, brown)  # eave
  fill_box(2,  6, 2,  15, 6, 13, brown)  # ridge step
```

Remember: switching `ROOF_OFF` true → false leaves the prior roof voxels
behind. Use `press_action("save_and_reload")` to reload clean.
