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
