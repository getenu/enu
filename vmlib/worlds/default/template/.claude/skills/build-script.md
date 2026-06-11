# Procedural and Animated Builds

Create voxel structures using turtle-style movement — ideal for spirals, towers,
fractals, and organic shapes. Also covers animated builds (doors, platforms, etc.)
using the state machine `loop:` system.

Full, verified scripts live in `.claude/examples/` — see its README for
an index. Prefer copying one and adapting it over writing from scratch.

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

Touch both files; Enu loads them and manages `level.json` itself.

## Movement-Based Building

The turtle draws voxels by moving. Builds draw instantly by default
(speed 0); set `speed = 1` or higher only to watch the drawing happen.

```nim
color = brown   # current draw color
drawing = true  # voxels placed while moving (default: true for builds)

forward 10      # draw 10 blocks forward
right 5         # draw 5 blocks right
up 3            # draw 3 blocks up
turn right      # turn 90° clockwise
turn left       # turn 90° counter-clockwise
turn 45.0       # turn by degrees
lean back, 30   # pitch 30°
lean right, 10  # roll 10°

save()          # save position + orientation + color
restore()       # restore the save
```

Name locals and proc params carefully: bare words like `height`,
`width`, `radius`, `size`, and `color` are unit accessors, and a local
or proc param with one of those names resolves to the accessor instead.
`home` is also taken (a built-in position offset, usable as `go home` —
but not a `Vector3`, so don't pass it to `me.go()`). Use `h`, `w`,
`rad`, `tall`, `col`, etc.

## Prototypes (`name X`)

Prototype names use `CamelCase` — `name Tower(...)`, `name Door(...)`.
The name becomes a type, so it reads as one.

The unit's id is `build_` + snake_case of the name: `name FlyerShip`
makes the unit `build_flyer_ship`, and Enu renames the script and data
files to match. Name the files that way from the start
(`scripts/build_flyer_ship.nim`) so the id you pass to
`wait_for_script` is the one the unit actually has.

> **⚠️ Never instantiate a prototype from inside its own script.** A build
> script that does `name Foo` *is* the `Foo` prototype — so calling `Foo.new(...)`
> in that same script makes the prototype instantiate **itself**, recursively,
> with no depth limit. It spawns an unbounded chain, floods the engine with
> `det == 0` errors, and **crashes Enu** — and re-crashes the level on every
> reload until the persisted files are deleted by hand.
>
> **Rule: define a prototype in one script; instantiate it from a *different*
> script** (another build, the player, or `eval`). To draw a one-off object,
> just draw it directly — don't use `name`/`.new` at all.

Rules that keep prototypes working:

- **Capture params into locals before drawing.** Passing a param straight
  into a drawing call resolves to its accessor, not its value:
  `let h = height` then `h.times: ...`.
- **Don't declare a `color` param.** `.new()` has a built-in `color`
  (default **eraser**) that silently shadows it — and a turtle-drawn
  instance paints in the unit color, so an eraser-colored instance draws
  its whole shape invisibly. Callers pass `color = ...` to `.new()`.
- **Proto-typed params default to the proto object**:
  `name Button(door = Door, pause = 5)` — see `.claude/examples/button.nim`.
- **Cover local `(0, 0, 0)`.** Every Build starts with a default block
  there (how the in-game block tool creates builds). If the proto's
  voxels don't cover it, it shows through as a stray block — draw over
  it, or erase it with `place(0, 0, 0, eraser)`.
- **Spawn at `y = 0`** so the build's lowest voxel rests on the ground:
  `Tower.new(height = 10, position = vec3(5, 0, -20))`.
- Spawner scripts set `drawing = false` so the spawner unit itself
  places no blocks.
- **Proto self-copies are hidden by default** (`show_prototypes` is
  false). Add `show = true` to the proto script while developing it so
  you can see what you're drawing, and remove it when the proto is
  done. Regular (non-proto) scripts show by default.

Reference pair: `.claude/examples/tower.nim` + `.claude/examples/tower_cluster.nim`
(randomised instances), `.claude/examples/spiral_tree.nim` +
`.claude/examples/tree_showcase.nim` (params + internal randomness).

## Scaled-down prototypes (furniture etc.)

For objects that don't read as themselves at 1 m³ resolution (chairs,
beds, fixtures), draw the prototype at higher internal voxel resolution
and set `scale = 0.25` (or similar). The internal detail makes it
recognisable; the scale keeps it human-sized. Scale things to fit a
space or a scene — not for detail's own sake. A pyramid is fine at full
scale with 1 m blocks (`.claude/examples/pyramid.nim`); a chair is not.

```nim
## Queen-size bed. 8x5x12 internal voxels at scale 0.25 = 2 × 1.25 × 3 m.
name BedQueen
scale = 0.25

box(width = 8, height = 2, depth = 12, color = brown)             # frame
box(width = 8, height = 2, at = position + vec3(0, 2, -10), depth = 11, color = white)  # mattress
box(width = 8, height = 6, depth = 1, color = brown)              # headboard
box(width = 3, height = 1, at = position + vec3(1, 4, -1), depth = 2, color = white)    # left pillow
box(width = 3, height = 1, at = position + vec3(4, 4, -1), depth = 2, color = white)    # right pillow
box(width = 8, height = 1, at = position + vec3(0, 4, -3), depth = 4, color = blue)     # blanket
```

Instantiate: `BedQueen.new(position = vec3(4, 0, -116))`

### Footprint of a scaled instance

`position` places the prototype's local `(0, 0, 0)` (or its anchor —
below). The instance extends along the proto's width / height / depth,
scaled: `box(width = 8, …)` at scale 0.25 → 2 m wide. So
`BedQueen.new(position = vec3(4, 0, -116))` occupies world
`(4..6, 0..0.5, -116..-113)` — the NW-bottom corner is the position,
*not* the centre.

To check clearance before placing, query the predicted world AABB:

```nim
if box_is_free(DiningChair.bounds_at(vec3(4, 0, -103), rotation = 90)):
  DiningChair.new(position = vec3(4, 0, -103), rotation = 90)
```

(`unit.bounds`, `a.overlaps(b)`, and `units_overlapping(box)` cover
already-placed units — see the level CLAUDE.md's bounds-query list.)

### Per-instance transform: rotation and scale

`position`, `rotation` (degrees around world Y), and `scale` are
`.new(...)` parameters as well as mutable fields on the instance:

```nim
let c = DiningChair.new(
  position = vec3(5, 0, -10), rotation = 90.0, scale = 0.3
)
c.rotation = -90.0   # or mutate after construction
```

(`scale = 0` and `rotation = 0` mean "not specified" — the proto's own
values keep applying.)

### Designing protos for rotation: the `anchor:` block

Without an anchor, `position`/`rotation` pivot around the proto's local
`(0, 0, 0)` — rotating swings the body around that corner. The
`anchor:` block declares where the pivot lives in the proto's local
voxel frame. Inside it, turtle commands accumulate into the anchor pose
— no voxels are placed, the unit doesn't move. Run it at the top of the
proto, before drawing:

```nim
name DiningChair
scale = 0.25

anchor:
  forward 1   # move pivot into the middle of the depth
  right 1     # ...and the middle of the width
```

Now `position` places the seat centre and `rotation` spins in place —
four chairs around a table need no offset arithmetic
(`.claude/examples/furniture_plaza.nim`).

The anchor is also a *direction*: `turn` inside the block changes the
unit's intrinsic forward, so `move me; forward 10` moves along the
visually-drawn front. Live re-anchoring works on instances too
(`c.anchor: forward 2`). Skip the anchor for structural pieces drawn
from a corner (walls, floors) that you never rotate.

## Patterns

Big worked examples (towers, castles, trees, skyscrapers) are in
`.claude/examples/` — copy and adapt. Small derivable patterns:

### Spiral staircase
```nim
color = brown
80.times:
  forward 3
  turn 18.0     # 18° = 20 steps per full circle
  up 1
```

### Drifting polygon tower
Walk a polygon but over- or under-turn each corner; every ring lands
slightly rotated and the shaft twists (`.claude/examples/candy_tower.nim`).

### Recursive branching
Pitch the turtle vertical, then at each split ROLL around the branch
axis before pitching away from it — without the roll, branches fork in
one plane and the tree becomes a vine (`.claude/examples/fractal_tree.nim`).

### Grid of instances (city)
```nim
drawing = false
seed = 42

10.times(row):
  10.times(col):
    drawing = false
    draw_position = ((col * 15).float, 0.0, (row * 15).float)
    drawing = true
    color = random(red, green, blue, black, white)
    Tower.new(height = 10 .. 50, sides = 3 .. 6)
```

## Animated Builds

After drawing, use `move me` to switch from build mode to move mode,
then animate with turtle commands — directly in a `forever:` loop for
simple motion, or with the `loop:` state machine for behavior. Move
mode interpolates smoothly on its own; don't add sleeps to animation
loops unless you want the motion to pause (`sleep 2`, always with a
duration).

### Rotating a build: which axis, and where it pivots

In move mode, `turn` and `lean` rotate the **whole unit**, and rotation
**always pivots on the unit's origin `(0, 0, 0)`** (the build's
`data/<id>/<id>.json` position). Which rotation you get:

| command | rotates around | use it for |
|---------|----------------|------------|
| `turn left/right N` | vertical **Y** (yaw) | carousels, lighthouse beams — anything on a vertical axle |
| `turn up/down N` | the left-right axis (pitch) | a drawbridge lifting at its hinge, a seesaw |
| `lean left/right N` | the **forward** axis (roll) | **windmills, Ferris wheels** — anything spinning in a vertical plane facing the viewer |
| `lean back/forward N` | the left-right axis (pitch) | tilting / leaning |

(`turn forward/back` and `lean up/down` raise an error — those don't exist.)

The classic mistake: drawing windmill blades in the X-Y plane and
spinning them with `turn` (yaw), which sweeps them flat like a revolving
door. Use `lean` (roll) so they spin in their own plane:

```nim
# Blades centred on the hub at the origin so they spin in place. ROLL, not yaw.
move me
speed = 30
forever:
  lean right, 4.0
```

**Pivot = the origin.** To **spin in place**, centre the geometry on
`(0,0,0)`; off-centre geometry **orbits** the origin. To **hinge**, put
the origin at the hinge and draw the part extending away from it:

```nim
box(width = 8, height = 1, depth = 10, color = brown)   # deck, hinge at origin
move me
speed = 20
forever:
  turn up, 70     # raise the far end (pitch around the hinge)
  sleep 2
  turn down, 70
  sleep 2
```

**Speed:** rotation rate ≈ degrees-per-command. To spin faster, raise
the per-step degrees (`turn right, 5` not `1.5`) — not just `speed`.

**Use the turtle commands, not position math.** Drive motion with
`turn`/`lean`/`up`/`forward`, not by computing `position.y` deltas with
`sin()`. The turtle commands read better and pivot correctly.

### `move me` animates the WHOLE unit — split a moving part into its own build

A build animates only as a whole. To move **just one part** — windmill
blades on a static tower, a pendulum, a drawbridge deck — that part must
be a **separate build**. Positioning it:

- Its **json origin is both where it sits AND its rotation pivot** —
  place the origin at the hinge/hub, not the centre of mass.
- **Offset it to clear the static geometry** — a fraction of a voxel
  off the shared plane stops z-fighting (blades in front of the tower,
  a sliding door at `z + 0.1` from its wall).
- Give it a **contrasting colour** so it reads against what's behind it.

### Simple motion

```nim
# Rotating platform
box(width = 10, height = 1, depth = 10, color = brown)
move me
speed = 30
forever:
  turn right, 5.0
```

```nim
# Oscillating lift
box(width = 3, height = 1, depth = 3, color = white)
move me
speed = 6
forever:
  up 6
  down 6
```

### Doors, buttons, collectibles

See `.claude/examples/door.nim` + `.claude/examples/button.nim` + `.claude/examples/doorway.nim`
for the full wired system (sliding pocket door, player-pressed button,
cross-unit `door.open = true`), and `.claude/examples/coin.nim` for a
player-touch collectible. The traps they encode: pass `color` to
`.new()`, proto-object param defaults, state procs before the `loop:`,
and the z-fighting nudge.

## State Machine Reference

```nim
# State procs are defined BEFORE the loop:
-my_state:
  forward 5
  sleep 2

loop:
  # Unconditional start state
  nil -> my_state

  # Rename a transition (sleep here is the built-in idle state)
  nil -> sleep as waiting

  # Conditional transition
  if condition:
    my_state -> other_state

  # Multiple sources, with a side effect
  (state_a, state_b) ==> new_state do:
    say "Switching!"
```

The loop runs every frame; a state's body runs while the state is
active. `sleep N` inside a state pauses it for N seconds. The bare
`sleep` *state* (`nil -> sleep as waiting`) idles the unit until a
transition moves it — use it for things that wait on a flag, like a
closed door.
