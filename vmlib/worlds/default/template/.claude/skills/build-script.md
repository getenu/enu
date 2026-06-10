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

> **⚠️ Never instantiate a prototype from inside its own script.** A build
> script that does `name Foo` *is* the `Foo` prototype — so calling `Foo.new(...)`
> in that same script makes the prototype instantiate **itself**, recursively,
> with no depth limit. It spawns an unbounded chain
> (`build_foo_build_foo_..._instance_1_...`), floods the engine with `det == 0`
> errors, and **crashes Enu**. Worse, `name Foo` persists a *second* build
> (`build_foo`) carrying the same `.new` call, so the level **re-crashes on every
> reload** until both are deleted by hand.
>
> **Rule: define a prototype in one script; instantiate it from a *different*
> script** (another build, the player, or `eval`). Never write
> `YourProto.new(...)` in the file that declares `name YourProto`. To draw a
> one-off object (rocket-on-a-pad, etc.) without a reusable proto, just draw it
> directly with `box`/turtle calls — don't use `name`/`.new` at all.

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
scale = 0.25

box(width = 8, height = 2, depth = 12, color = brown)             # frame
box(width = 8, height = 2, at = position + vec3(0, 2, -10), depth = 11, color = white)  # mattress
box(width = 8, height = 6, depth = 1, color = brown)              # headboard at the back face
box(width = 3, height = 1, at = position + vec3(1, 4, -1), depth = 2, color = white)    # left pillow
box(width = 3, height = 1, at = position + vec3(4, 4, -1), depth = 2, color = white)    # right pillow
box(width = 8, height = 1, at = position + vec3(0, 4, -3), depth = 4, color = blue)     # blanket
```

Instantiate:

```nim
BedQueen.new(position = vec3(4, 1, -116))
```

### Footprint of a scaled instance

The `position` argument places the prototype's local `(0, 0, 0)` at that
world coord. The instance then extends along the proto's width / height /
depth (scaled):

- `box(width = 8, …)` covers 8 voxels along the proto's +X → 8 × 0.25 = 2 m wide
- `box(_, _, depth = 12, …)` covers 12 voxels along the proto's -Z → 12 × 0.25 = 3 m deep

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

### Designing protos for rotation: the `anchor:` block

Without an anchor, `position`/`rotation` pivot around the proto's local
`(0, 0, 0)` — which is the turtle's starting cell. Rotating swings the
body around that corner; setting `position = vec3(x, y, z)` places the
corner there, not the centre.

The `anchor:` block declares where the proto's *pivot* lives in its
local voxel frame. Inside the block, turtle commands (`forward`,
`right`, `up`, `turn`, `lean`) accumulate into the anchor pose — no
voxels are placed, the unit is not moved, the turtle's pre-block state
isn't touched. Run it at the top of the proto, before any drawing.

```nim
## Dining chair: 2 wide × 5 tall × 2 deep voxels. Anchor at the centre
## of the seat so `position` places the seat centre and `rotation`
## pivots around it. Backrest is on the proto's +Z face.
name DiningChair
speed = 0
scale = 0.25

anchor:
  forward 1   # move pivot into the middle of the depth
  right 1     # ...and the middle of the width

box(width = 2, height = 1, depth = 2, color = brown)             # legs row
box(width = 2, height = 1, at = position + vec3(0, 1, -1),
    depth = 2, color = brown)                                    # seat
box(width = 2, height = 3, at = position + vec3(0, 2, 0),
    depth = 1, color = brown)                                    # backrest at proto +Z face
```

Place four chairs around a table on clean grid coords:

```nim
DiningChair.new(position = vec3(4.5, 1, -104), rotation = 0)    # N
DiningChair.new(position = vec3(4.5, 1, -103), rotation = 180)  # S
DiningChair.new(position = vec3(5.0, 1, -103.5), rotation = 270) # E
DiningChair.new(position = vec3(4.0, 1, -103.5), rotation = 90)  # W
```

No half-extent offset arithmetic in the call sites — the chair's centre
goes exactly where you ask, and rotation spins it in place.

The anchor is also a *direction*, not just a point. `turn` inside the
block changes the unit's intrinsic forward, so `move me; forward 10`
moves the unit along the visually-drawn forward instead of the proto's
hard-coded `-Z`.

Live re-anchoring works on instances too — visibly moves/reorients,
since the unit is already on screen:

```nim
let c = DiningChair.new(position = vec3(5, 1, -10))
c.anchor:
  forward 2   # nudge the pivot deeper into the seat
```

When *not* to bother with an anchor: structural pieces drawn from a
corner (walls, floors, long beams) that you never rotate. The default
identity anchor + `box(width, height, depth)` at the turtle is fine.

> **TODO (Enu API gap):** instance footprints (post-scale, post-rotation
> world AABB) still aren't queryable, so there's no built-in collision
> check between an instance and walls / other instances. The anchor
> pins down the reference point that query would key off; track each
> one explicitly in the `/build-plan` Inventory table for now.

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

### Rotating a build: which axis, and where it pivots

In move mode, `turn` and `lean` rotate the **whole unit**, and rotation
**always pivots on the unit's origin `(0, 0, 0)`** — the build's local origin
(its `data/<id>/<id>.json` position). Which rotation you get:

| command | rotates around | use it for |
|---------|----------------|------------|
| `turn left/right N` | vertical **Y** (yaw) | carousels, merry-go-rounds, a sweeping lighthouse beam — anything on a vertical axle |
| `turn up/down N` | the left-right axis (pitch / tumble) | a drawbridge lifting at its hinge, a seesaw |
| `lean left/right N` | the **forward** axis (roll) | **windmills, Ferris wheels** — anything spinning in a vertical plane that faces the viewer |
| `lean back/forward N` | the left-right axis (pitch) | tilting / leaning |

(`turn forward/back` and `lean up/down` raise an error — those don't exist.)

The classic mistake: drawing windmill/Ferris-wheel blades in the X-Y plane and
spinning them with `turn` (yaw), which sweeps them flat like a revolving door.
Use `lean` (roll) so they spin in their own plane:

```nim
# Blades centred on the hub at the origin so they spin in place. ROLL, not yaw.
move me
speed = 30
forever:
  lean right, 4.0
  sleep()
```

**Pivot = the origin.** To **spin in place**, centre the geometry on `(0,0,0)`
(negative coords, or `at = vec3(-w/2, ...)`); off-centre geometry **orbits** the
origin instead. To **hinge**, put the origin at the hinge and draw the part
extending away from it — e.g. a drawbridge deck drawn from the origin, lifted by
pitching up around that near end:

```nim
speed = 0
box(width = 8, height = 1, depth = 10, color = brown)   # deck, hinge at origin
move me
speed = 20
forever:
  turn up, 70     # raise the far end (pitch around the hinge)
  sleep 2
  turn down, 70
  sleep 2
```

**Speed:** rotation rate ≈ degrees-per-command. To spin faster, raise the
per-step degrees (`turn right, 5` not `1.5`) — not just `speed`.

**Use the turtle commands, not position math.** Drive motion with
`turn`/`lean`/`up`/`forward`, not by computing `position.y` deltas with `sin()`.
The turtle commands read better and pivot correctly.

### `move me` animates the WHOLE unit — split a moving part into its own build

A build animates only as a whole. To move **just one part** — a windmill's
blades on a static tower, a clock's pendulum, a drawbridge deck on a static
gatehouse — that part must be a **separate build**. (Animating the pendulum from
inside the clock-tower script slides the *entire tower*.) Positioning that
separate part (a "clone"):

- Its **`data/<id>/<id>.json` origin is both where it sits AND its rotation
  pivot** — place the origin at the hinge/hub, not the centre of mass.
- **Offset it to clear the static geometry.** Windmill blades belong *in front
  of* the tower (offset toward the viewer in +Z), not inside it, or they clip
  through — especially if the tower tapers outward toward the base.
- Give it a **contrasting colour** so it reads against whatever's behind it (red
  blades on a white tower, not white-on-white).

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

box(width = 10, height = 1, depth = 10, color = brown)   # 10×10 platform

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

box(width = 3, height = 1, depth = 20, color = brown)

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
box(width = 2, height = 2, depth = 2, color = red)

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
