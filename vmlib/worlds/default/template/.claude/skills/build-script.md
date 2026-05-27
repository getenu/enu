# Procedural and Animated Builds

Create voxel structures using turtle-style movement — ideal for spirals, towers,
fractals, and organic shapes. Also covers animated builds (doors, platforms, etc.)
using the state machine `loop:` system.

## Usage

```
/build-script <description>
```

## Files Needed

**`data/<name>/<name>.json`** — world position:
```json
{
  "id": "build_tower",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [0.0, 0.0, -30.0]
  },
  "start_color": "BROWN",
  "edits": {}
}
```

**`scripts/<name>.nim`** — Nim script

Add to `level.json` load_order.

## Movement-Based Building

The turtle draws voxels by moving. `speed = 0` builds instantly.

```nim
speed = 0       # build instantly (vs speed = 1 for animated building)
color = brown   # current draw color
drawing = true  # voxels placed while moving (default: true for builds)

forward 10      # draw 10 blocks forward
right 5         # draw 5 blocks right
up 3            # draw 3 blocks up
turn right      # turn 90° clockwise
turn left       # turn 90° counter-clockwise
turn 45.0       # turn by degrees
lean back, 30   # tilt forward 30° (affects forward/back direction)
lean forward    # tilt back 90°

save()          # save position + orientation
restore()       # restore saved position + orientation
```

## Naming Convention

Prototype names use `CamelCase` — `name Tower(...)`, `name WallSegment(...)`,
`name Door(...)`. The name becomes a type, so it reads as one.

Origin tip: every Build starts with a default block at local `(0, 0, 0)` —
how the in-game block tool creates a build. If the prototype's voxels don't
naturally cover that voxel, the default block shows through. Either draw
over `(0, 0, 0)`, or spawn instances at `y = 1` so the default block lands
above ground:

```nim
Tower.new(height = 10, position = vec3(5, 1, -20))
```

## Scaled-down prototypes (furniture etc.)

For objects that don't read as themselves at 1 m³ resolution (chairs,
beds, fixtures), draw the prototype at higher internal voxel resolution
and set `scale = 0.25` (or similar) so the displayed object is the
right size. The internal detail makes it recognisable; the scale keeps
it human-sized.

Pattern (example — design protos for whatever your build needs, this is
just a representative one):

```nim
## Queen-size bed. 8x5x12 internal voxels at scale 0.25 = 2 × 1.25 × 3 m.
name BedQueen
speed = 0
if not is_instance:
  show = false
  quit()

scale = 0.25

fill_box(0, 0, 0, 7, 1, 11, brown)   # frame
fill_box(0, 2, 1, 7, 3, 11, white)   # mattress
fill_box(0, 0, 0, 7, 5, 0, brown)    # headboard
fill_box(1, 4, 1, 3, 4, 2, white)    # pillows
fill_box(4, 4, 1, 6, 4, 2, white)
fill_box(0, 4, 8, 7, 4, 11, blue)    # blanket
```

Instantiate:

```nim
BedQueen.new(position = vec3(4, 1, -116))
```

### Footprint of a scaled instance

The `position` argument places the prototype's local `(0, 0, 0)` at that
world coord. The instance then extends `+X`, `+Y`, `+Z` by
`(voxel_count × scale)`:

- `fill_box(0, _, _, 7, …)` covers 8 voxels (`0..7` inclusive) → 8 × 0.25 = 2 m wide
- `fill_box(_, _, 0, _, _, 11)` covers 12 voxels → 12 × 0.25 = 3 m deep

So `BedQueen.new(position = vec3(4, 1, -116))` occupies world
`(4..6, 1..1.5, -116..-113)`. The displayed object's NW-bottom corner is
the position, *not* the centre.

### Limitations to know about

> **TODO (Enu API gap):** there's no built-in collision check between
> scaled instance footprints and walls, doors, or other instances. To
> avoid overlap, list each instance's footprint explicitly in the
> `/build-plan` Inventory table and verify by walking through after
> placing.

### Per-instance transform: rotation and scale

`position`, `rotation` (degrees around world Y), and `scale` are all
`.new(...)` parameters as well as mutable fields on the instance:

```nim
# Create rotated + sized in one line:
let c = DiningChair.new(
  position = vec3(5, 1, -10), rotation = 90.0, scale = 0.3
)

# Or mutate after construction:
let d = DiningChair.new(position = vec3(7, 1, -10))
d.rotation = -90.0
d.scale = 0.5
```

(`scale = 0` is treated as "not specified" so the proto's own
`scale = ...` line in its body keeps applying. Same for
`rotation = 0`.)

### Designing protos for rotation

Rotation pivots around the instance's `position` — which is the proto's
local `(0, 0, 0)`. If you draw your proto starting at `(0, 0, 0)` and
filling in `+X`/`+Y`/`+Z` (the natural pattern for `fill_box`), the
proto's origin is its **NW-bottom corner**, and rotating the instance
swings the body around that corner. The displayed object ends up in a
different world location than the un-rotated version.

If a proto is going to be rotated — chairs around a table, lamps in
different orientations, anything multi-facing — draw it around the
origin instead, using negative voxel coordinates:

```nim
## Dining chair: 2 wide x 5 tall x 2 deep, centred so rotation pivots
## around the chair's middle. Backrest fixed at the -Z (proto-north)
## face; use `rotation` on the instance to face it the right way.
name DiningChair
speed = 0
if not is_instance:
  show = false
  quit()

scale = 0.25

# Four legs around the origin
fill_box(-1, 0, -1, -1, 0, -1, brown)
fill_box( 0, 0, -1,  0, 0, -1, brown)
fill_box(-1, 0,  0, -1, 0,  0, brown)
fill_box( 0, 0,  0,  0, 0,  0, brown)

# Seat slab
fill_box(-1, 1, -1, 0, 1, 0, brown)

# Backrest at -Z face (chair's "north" side)
fill_box(-1, 2, -1, 0, 4, -1, brown)
```

Place four chairs around a table by varying `rotation`:

```nim
DiningChair.new(position = vec3(4.5, 1, -104.75), rotation = 0)   # N
DiningChair.new(position = vec3(4.5, 1, -103),    rotation = 180) # S
DiningChair.new(position = vec3(5.75, 1, -103.875), rotation = 270) # E
DiningChair.new(position = vec3(3.25, 1, -103.875), rotation = 90)  # W
```

When *not* to centre the origin: structural pieces that grow in a
single direction (walls, floors, long beams) are simpler to author with
the NW-corner origin pattern, and they're rarely rotated dynamically
anyway. Use the centred pattern specifically for instances that need
arbitrary-angle placement.

> **TODO (Enu API gap):** instance footprints (post-scale,
> post-rotation world AABB) aren't queryable, so there's no built-in
> collision check between an instance and walls / other instances.
> Track each one explicitly in the `/build-plan` Inventory table.

> **TODO (Enu API gap):** instance footprints (post-scale,
> post-rotation world AABB) aren't queryable, so there's no built-in
> collision check between an instance and walls / other instances.
> Track each one explicitly in the `/build-plan` Inventory table.

## Patterns

### Polygon tower (N sides)
```nim
name Tower(height = 50, sides = 4, length = 10, twist = 0.0)
speed = 0

height.times:
  sides.times:
    forward length
    turn 360.0 / sides.float + twist
  up 1
```

Spawn multiple: `Tower.new(height = 60, sides = 6, color = blue)`

### Spiral staircase
```nim
speed = 0
color = brown
80.times:
  forward 3
  turn 18.0     # 18° = 20 steps per full circle
  up 1
```

### Sine-wave sculpture
```nim
import math
speed = 0
color = blue

360.times:
  turn 1.0
  save()
  lean back, 20.0
  150.times(i):
    if 1 in 500:
      color = cycle(white, green)
    drawing = 2 in 3
    forward 1
    lean back, sin(i.float * 0.06) * 3.0
  restore()
```

### Fractal tree (recursive)
```nim
speed = 0
import math

proc branch(depth: int, len: float) =
  if depth == 0: return
  color = if depth > 2: brown else: green
  forward len
  save()
  turn left, 35.0
  branch(depth - 1, len * 0.65)
  restore()
  save()
  turn right, 35.0
  branch(depth - 1, len * 0.65)
  restore()
  back len

branch(6, 10)
```

### Maze walls (random seed)
```nim
speed = 0
seed = 42
color = black

-ring:
  5.times(side):
    color = if 1 in 10: cycle(blue, red, white) else: black
    drawing = 1 in 4 or side notin {2, 3}
    forward 10
    lean back, 72.0   # 360/5
  turn -1.0 .. 1.0
  left 0.5

turn left
1000.times:
  ring()
  if 1 in 30:
    color = cycle(black, white, black)
```

### Grid of instances (city)
```nim
drawing = false
speed = 0
seed = 42

10.times(row):
  10.times(col):
    drawing = false
    # Move to grid position
    let x = col * 15
    let z = row * 15
    draw_position = (x.float, 0.0, z.float)
    drawing = true
    let h = 10 .. 50
    let s = 3 .. 6
    color = random(red, green, blue, black, white)
    tower.new(height = h, sides = s)
```

## Animated Builds

After drawing, use `move me` to switch from build mode to move mode,
then use the `loop:` state machine for animation.

### Sliding door
```nim
name Door(color = green, open = false, width = 20, height = 11)
speed = 0

# Draw the door
height.times:
  right width
  turn 180
  up 1

# Switch to move mode
move me
scale = 1.05
forward 0.05    # slight offset to prevent z-fighting
speed = 5

loop:
  nil -> sleep as door_closed
  if open:
    door_closed -> left(home + width) as door_open
  else:
    door_open -> right(home) as door_closed
```

Open from another script: `var my_door = Door.new(...); my_door.open = true`

### Rotating platform
```nim
import math
speed = 0
color = brown

# Build a 10x1x10 platform
fill_box(0, 0, 0, 9, 0, 9, brown)

move me
speed = 50
var t = 0.0
forever:
  t += 1
  turn right, 1.0   # rotate 1° per tick
  sleep()
```

### Oscillating bridge (up/down)
```nim
import math
speed = 0
color = brown

fill_box(0, 0, 0, 3, 0, 20, brown)

move me
speed = 100
var t = 0.0
forever:
  t += 0.03
  let target_y = sin(t) * 3.0
  # move to absolute Y height
  let current_y = position.y - start_position.y
  up target_y - current_y
  sleep()
```

### Button-triggered door
```nim
# In button script (build_button.nim):
name Button(door: Door = nil, pause = 5)

speed = 0
color = red
fill_box(0, 0, 0, 1, 1, 1, red)

move me
speed = 10

loop:
  nil -> sleep as idle
  if Player.hit:
    idle -> press
  -press:
    if door != nil:
      door.open = true
    color = green
    sleep pause
    door.open = false
    color = red
```

## State Machine Reference

```nim
loop:
  # Unconditional start state
  nil -> state_name

  # Rename a transition
  nil -> sleep as my_state

  # Conditional transition
  my_state -> other_state if condition

  # Transition with side effect
  (state_a, state_b) ==> new_state do:
    say "Switching!"

  # Inline action state
  -my_state:
    forward 5
    sleep 2
```

State machine runs every frame. Actions (`-state:`) run once per activation.
`sleep` pauses until the next frame. `sleep 2` pauses for 2 seconds.
