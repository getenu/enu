## Turtle-aware shape API + queries — exploration sketch
##
## Today's `fill_box(x1, y1, z1, x2, y2, z2, color)` takes raw local
## voxel coords and ignores the turtle entirely. That gives you a
## predictable absolute-coords drawing primitive, but it doesn't
## compose with `forward`, `right`, `up`, `turn` — the two halves of
## the Logo API live in different worlds.
##
## This file sketches a Logo-first version of the shape primitives,
## plus the bounding-box / clearance queries we want for navigation
## and animation. Each section labels the questions still open and,
## where the right answer isn't obvious, shows two or three call
## sites side-by-side so we can pick by reading them.
##
## Nothing here is wired up yet. Treat it as a proposal to react to.

# =====================================================================
# Section 1 — `box` (the old `fill_box`)
# =====================================================================

## Rename: `fill_box` → `box`. A `fill = true` parameter switches
## between solid and shell. Default `fill = true` because solid blocks
## are the common case for filling rooms, walls, floors.
##
## All shape primitives default to *starting from the turtle* (its
## current draw_position). Override by passing `from = vec3(...)` or
## `at = vec3(...)` — see naming question below.
##
## Width / height / depth named params are preferred. The user types
## the dimensions they're thinking about, not corner coordinates.

# ---------- 1a. Origin: where does the turtle sit on the box? --------

## **Default: back-bottom-left corner of the box, in the turtle's
## local frame.**
##
## Width extends along the turtle's local right (+X), height along
## +Y (up), depth along the turtle's local forward (-Z in the
## default-facing case, but always *whatever direction the turtle is
## currently pointing*).
##
## The key identity:
##
##   box(width = 1, height = 1, depth = 5)
##
## paints exactly the voxels that
##
##   forward 5
##   back 5
##
## would, and leaves the turtle at the same spot it started. That
## anchors the mental model to the rest of the turtle API.
##
## With the turtle facing default (north, -Z), the box extends:
##   - east (+X) by `width`
##   - up   (+Y) by `height`
##   - north (-Z) by `depth`
## So the turtle sits at the **south-west-bottom** corner of the
## displayed box (back of the box from the turtle's perspective,
## ground floor, left edge).

box(width = 6, height = 3, depth = 4, color = brown)
# At turtle position, axis-aligned to turtle's heading.

## A `pivot` param overrides the default when you want the turtle to
## land somewhere else on the box — centre for furniture-style "drop
## a thing here", bottom_centre for columns/lamps/trees:

box(width = 6, height = 3, depth = 4, color = brown, pivot = corner)        # default
box(width = 6, height = 3, depth = 4, color = brown, pivot = centre)        # full centre
box(width = 6, height = 3, depth = 4, color = brown, pivot = bottom_centre) # column/tree

## (Half-voxel issues on odd dimensions with `centre` and
## `bottom_centre`: snap to the −X / −Z side of the half-voxel.
## Document the rule once; consistent across all shapes.)

# ---------- 1b. Overriding the turtle ---------------------------------

## `box` defaults to the turtle's full transform (position + heading).
## Three explicit forms to override, ordered by how often agents and
## humans actually reach for them:

# 1. Axis-aligned at a coord (most common; matches today's mental model)
box(width = 6, height = 3, depth = 4, color = brown,
    at = vec3(0, 1, -10))

# 2. Axis-aligned, corner-to-corner. Direct port of today's fill_box,
#    handy when you already know the region's exact extents (e.g. "fill
#    this whole room").
box(at = vec3(0, 0, -10), to = vec3(9, 4, 0), color = brown)

# 3. At a coord with explicit yaw rotation (degrees, around world Y).
#    Matches `.new(rotation = …)` on instances.
box(width = 6, height = 3, depth = 4, color = brown,
    at = vec3(0, 1, -10), rotation = 45)

## The first form is what an agent or human writes 90% of the time:
## a vec3 and three dimensions, all named. The second form is the
## fallback when you're thinking in absolute corners. The third covers
## off-axis without exposing a full Transform.
##
## For arbitrary 6-DOF orientations (lean + yaw + roll together),
## an escape hatch:
##
##   box(width = 6, height = 3, depth = 4, color = brown,
##       transform = some_transform)
##
## Probably rare enough that the verbose name is fine — it's a sign
## you're doing something the simpler forms can't express.

# ---------- 1b'. drawing / scale / eraser semantics -----------------

## - `drawing = false` does **not** suppress `box` (or `sphere` /
##   `cylinder`). It only gates the per-step turtle moves
##   (`forward`/`back`/`left`/`right`/`up`/`down`). This makes
##   `drawing = false` + turtle walks + shape calls the canonical
##   way to compose a layout: the turtle navigates without leaving
##   a trail, and each `box`/`sphere`/`cylinder` places its solid.
##
## - The unit's `scale` is ignored by `box` (it applies at render
##   time as today). `box(width = 5)` always paints 5 voxels.
##
## - `color = eraser` erases, same as today.
##
## - Shell mode (`fill = false`) at off-axis rotations may have small
##   gaps where the OBB's face plane skims between voxel centres.
##   Acceptable — same Bresenham-style artefact as `forward N; turn θ`.

# ---------- 1c. Shell mode ------------------------------------------

## Solid fill is the common case; outline is occasionally useful for
## debug / wireframes.

box(width = 6, height = 3, depth = 4, color = brown)               # solid
box(width = 6, height = 3, depth = 4, color = brown, fill = false) # shell only

## A `wall = 1` param could control shell thickness later; default
## `fill = false` implies 1-voxel-thick shell. Not exploring further
## here — the common case is solid.

# ---------- 1d. Eraser / hollowing ----------------------------------

## `color = eraser` continues to work for hollowing. No API change.
## Existing pattern stays:
box(width = 6, height = 3, depth = 4, color = brown)
box(width = 4, height = 1, depth = 2, color = eraser,
    at = position + vec3(1, 1, 1))   # door opening

## (Once we have the placement query API, the inner-box coords
## become easier to express relative to the outer box's bounds —
## see Section 4.)

# ---------- 1e. Side-by-side: building a 10 × 5 × 16 floor + walls ---

# Today (fill_box):
fill_box(0, 0, 0, 9, 0, 15, brown)        # floor
fill_box(0, 1, 0, 9, 4, 0, white)         # back wall
fill_box(0, 1, 15, 9, 4, 15, white)       # front wall
fill_box(0, 1, 0, 0, 4, 15, white)        # west wall
fill_box(9, 1, 0, 9, 4, 15, white)        # east wall

# Proposed (turtle-relative `box`, walking the perimeter):
speed = 0
drawing = false
box(width = 10, height = 1, depth = 16, color = brown)  # floor at turtle
up 1
box(width = 10, height = 4, depth = 1, color = white)  # back wall
forward 15
box(width = 10, height = 4, depth = 1, color = white)  # front wall
back 15
box(width = 1, height = 4, depth = 16, color = white)  # west wall
right 9
box(width = 1, height = 4, depth = 16, color = white)  # east wall

# Where turtle-relative wins: the proportions live in width/height/depth
# (which you'd write anyway), and the *placement* is "where am I now."
# When the layout shifts, only the `forward 15` / `right 9` numbers move,
# not a coordinate in every `fill_box` line.

# ---------- 1f. `wall` and `floor` as thin wrappers ------------------

## With `box` heading-aware, the natural authoring helpers collapse
## to one-liners. Both leave the turtle at the far end of the shape
## (matches `forward length`) so they chain naturally into polygon
## walks and stair steps.

proc wall(length: int, height = default_wall_height, color = color) =
  box(width = length, height = height, depth = 1, color = color)
  forward length

proc floor(length: int, width = length, color = color) =
  box(width = width, height = 1, depth = length, color = color)
  forward length

# Rectangular house perimeter (4 walls + floor):
speed = 0
drawing = false
color = white

floor 10, 16, color = brown
2.times:
  wall 10
  turn right
  wall 16
  turn right

# Stairs — `floor` rasterises at the turtle's full orientation, so
# leaning the turtle 90° between treads draws the riser as a tilted
# floor. Same primitive, free composition with `lean`:
10.times:
  floor 3, 5     # tread
  lean back
  floor 3, 5     # riser (vertical face)
  lean forward

# =====================================================================
# Section 2 — `sphere`, `cylinder`
# =====================================================================

## `fill_sphere` and `fill_cylinder` already centre on a point; the
## natural turtle-default is "centre at the turtle."

## **Naming:** `size`, not `radius`. Easier for young authors, and it
## matches `box`'s `width = 1` = smallest-possible-wall convention
## (smallest sphere is `size = 1`, a 1-voxel ball; `size = 2` is
## roughly a 2-across ball; etc.).
##
## **Sphere pivot:** centre at the turtle.
## **Cylinder pivot:** centre of the bottom face. Cylinder axis is
## the turtle's local up.

sphere(size = 6, color = green)                       # at turtle
sphere(size = 6, color = green, at = vec3(5, 4, 0))

cylinder(size = 2, height = 6, color = brown)         # at turtle, up
cylinder(size = 2, height = 6, color = brown, at = some_unit.position)

## Cylinder axis = turtle's local up, so leaning the turtle tilts the
## cylinder (just like `box` and `wall` already do). Authors who want
## a always-world-vertical column can call it at the world origin or
## reset the turtle's lean first.

# ---------- 2a. Sphere/cylinder shell mode ---------------------------

sphere(size = 6, color = green, fill = false)         # hollow shell
cylinder(size = 8, height = 8, color = brown, fill = false)

# ---------- 2b. Tree built turtle-first ------------------------------

# Today:
fill_cylinder(0, 0, 5, 0, 0.6, brown)
fill_sphere(0, 8, 0, 3.0, green)

# Proposed (turtle-relative):
cylinder(size = 1, height = 6, color = brown)         # trunk
up 8
sphere(size = 6, color = green)                       # canopy

# =====================================================================
# Section 3 — Instance placement reads turtle by default
# =====================================================================

## `.new()` already accepts `position = vec3(...)`. Make `position`
## default to the turtle's current position so the four-towers example
## from the user's question Just Works:

drawing = false
Tower.new()
forward 20
Tower.new()
right 20
Tower.new()
back 20
Tower.new()
left 20
Tower.new()

## (`Tower.new()` with no args = at the turtle's draw_position. The
## existing `position = vec3(...)` keyword still works to override.)

# =====================================================================
# Section 4 — Bounding-box & clearance queries
# =====================================================================

## The shape primitives above know their own footprint at call time
## (width/height/depth literally describe it). The queries here let
## a script ask the same thing about *placed instances*, after scale,
## rotation, and anchor are applied.
##
## Type:
##
##   type WorldBox* = object
##     min*, max*: Vector3
##
##   proc size*(b: WorldBox): Vector3
##   proc centre*(b: WorldBox): Vector3
##   proc contains*(b: WorldBox, p: Vector3): bool
##   proc intersects*(a, b: WorldBox): bool
##   proc expanded*(b: WorldBox, margin: float): WorldBox

# ---------- 4a. `bounds` on any unit --------------------------------

let chair = DiningChair.new()        # at turtle
echo chair.bounds            # WorldBox in world coords
echo chair.bounds.size       # vec3(0.5, 1.25, 0.5)
echo chair.bounds.centre     # ≈ chair.position (anchor is at the seat centre)

## For Bots/Players: collider AABB. For Builds: voxel-tight AABB after
## scale + rotation + anchor. The existing `bounds_value: EdValue[AABB]`
## on Build (src/types.nim:306) is the storage hook; world composition
## happens in the getter.

# ---------- 4b. Pre-placement validation ----------------------------

## `proto_bounds(args...)` on a proto: "if I called .new with these
## args, what world AABB would the instance occupy?" Computed from the
## proto's static voxel bounds + the requested transform — no
## instantiate-then-destroy needed.

let proposed = DiningChair.proto_bounds(at = vec3(4.5, 1, -103))
if proposed.fits():
  DiningChair.new(at = vec3(4.5, 1, -103))
else:
  echo "won't fit"

## `fits(box: WorldBox): bool` = box is clear of all voxels and
## instance bounds in the current level (excluding the asking unit).

# ---------- 4c. Turtle-relative version -----------------------------

## If `.new()` defaults to the turtle, `proto_bounds` should too:

right 5
if DiningChair.proto_bounds().fits():
  DiningChair.new()

## Same call, no coordinates — placement is "here, where I'm standing."

# ---------- 4d. Auto-arrange chairs around a table ------------------

## With anchor + bounds, the four-chairs-around-a-table pattern
## becomes a loop instead of a coord table:

let table = DiningTable.new(at = vec3(3.5, 1, -104.5))
let tb = table.bounds

# At each of the four cardinal mid-edges of the table:
for (offset, rotation) in [
  (vec3(0, 0, -0.5), 0),     # south side, facing north
  (vec3(0, 0, +0.5), 180),   # north side, facing south
  (vec3(-0.5, 0, 0), 90),    # west side
  (vec3(+0.5, 0, 0), 270),   # east side
]:
  let chair_w = 0.5
  let pos = tb.centre + offset * (tb.size + vec3(chair_w, 0, chair_w)) / 2
  DiningChair.new(at = pos, rotation = rotation)

## Or, if `DiningChair.proto_bounds` lets us ask the chair's size
## without instantiating, drop the magic `chair_w = 0.5`:

let cw = DiningChair.proto_bounds().size

# ---------- 4e. Bots / animation use cases --------------------------

## The user's note: bounds + collision are useful for navigation and
## animation, not just authoring. Examples:

# A patrol bot avoiding clipping into furniture:
forever:
  let dest = position + forward_vec * 3
  if WorldBox.around(dest, radius = 0.5).fits(except = me):
    forward 3
  else:
    turn -45.0 .. 45.0
  sleep 0.1

# A door bot animating open only if the path is clear:
loop:
  nil -> closed
  if WorldBox.around(door.bounds.centre, radius = 1.0).clearance(others = [me]) > 0.5:
    closed -> opening
  ...

# A vendor that auto-reshelves products if a slot opens:
for slot_pos in shelf.slot_positions:
  if WorldBox.at(slot_pos, size = vec3(0.5, 0.5, 0.5)).fits():
    Product.new(at = slot_pos)

# ---------- 4f. `clearance` ----------------------------------------

## Surface-to-surface distance to the nearest other unit (or voxel).

let gap = chair.clearance         # to anything else in the level
let gap_to = chair.clearance(others = @[table])  # restricted set
if gap < 0.0:
  echo chair.id, " is overlapping something"

# ---------- 4g. Box construction helpers ---------------------------

## A few constructors that keep call sites readable:

WorldBox.at(centre = vec3(5, 1, -10), size = vec3(2, 1, 2))
WorldBox.from(corner = vec3(0, 0, -10), size = vec3(5, 3, 4))
WorldBox.around(point = vec3(5, 1, -10), radius = 1.0)   # cubic box of half-extent 1

## `WorldBox.around` is the one you'll reach for most often — "give me
## a metre of clearance around this point."

# =====================================================================
# Section 5 — open questions before implementation
# =====================================================================

## (Carried over from instance-query-api.md, narrowed.)
##
## 1. [resolved] Pivot default for `box`: back-bottom-left corner in
##    the turtle's local frame, so `box(w, h, d)` paints the same
##    voxels as `forward d; back d` (extended to a w × h cross-section).
##    `centre` and `bottom_centre` available via the `pivot` param.
##
## 2. Voxel-tight AABB for Builds: recompute whenever a voxel is
##    added/removed (cheap incremental update of min/max), or compute
##    lazily on first `bounds` call? Lazy is simpler; incremental is
##    free for animation that calls `bounds` every frame.
##
## 3. `proto_bounds` requires knowing the proto's static bbox without
##    running the body. Options: (a) authors declare `bbox = box(...)`
##    in the proto, (b) we instantiate once at registration time and
##    cache, (c) we don't support it and force the
##    instantiate-then-measure pattern. (b) is cheapest at call time
##    and avoids author burden.
##
## 4. [resolved] Should `box` and friends respect the turtle's
##    heading? Yes — `box` rasterises at the turtle's full transform
##    (origin + basis) by default, so off-axis boxes work naturally
##    and `wall`/`floor` collapse into one-line wrappers (Section 6).
##    The candy-cane spiral (`forward 10; turn 46`) demonstrates that
##    rasterised off-axis voxels are a feature, not an artefact to
##    engineer away. Snapping to cardinals would have killed that.

# =====================================================================
# Section 6 — `box` rasterisation algorithm + impl steps
# =====================================================================

## Goal: one primitive that handles every case — axis-aligned and
## off-axis — at the turtle's transform, an explicit coord, or a full
## Transform. The cardinal-axis case is no slower than today's
## `fill_box`; off-axis cases produce the same Bresenham-style
## stairstepping the existing `forward N; turn θ` patterns already
## yield, so the look is consistent across the whole API.

## ---------- 6a. OBB scan-conversion -------------------------------
##
## Given:
##   T          = world transform of the box (origin + basis)
##   w, h, d    = box dimensions (voxels)
##   pivot      = pivot_offset within the box (corner / centre /
##                bottom_centre — translated to a vec3 offset)
##   fill       = solid vs shell
##
## Algorithm:
##
##   1. Compute the box's 8 OBB corners in world space:
##         for each (x, y, z) in {0, w} × {0, h} × {0, d}:
##           corner_world[i] = T * (vec3(x, y, z) - pivot)
##      Take min/max across the 8 corners → world AABB. This bounds
##      the set of voxels that could possibly be inside the box.
##
##   2. Inverse basis once:
##         inv = T.basis.inverse        # 3×3
##
##   3. For each integer (x, y, z) inside the world AABB:
##         centre_world = vec3(x + 0.5, y + 0.5, z + 0.5)
##         local = inv * (centre_world - T.origin) + pivot
##         if 0 <= local.x <= w
##         and 0 <= local.y <= h
##         and 0 <= local.z <= d:
##           # inside the OBB; for fill = false, also require
##           # min(local.x, w - local.x, local.y, h - local.y,
##           #     local.z, d - local.z) <= 0.5
##           draw_voxel((x, y, z), color)
##
## Per-voxel cost: one matrix-vec multiply + three range checks.
## Cardinal case: AABB equals (w × h × d), inner test trivially true
## (or skipped via a fast-path), so it matches today's fill_box work.
## Off-axis: AABB is at most √3 × the box volume (worst case 45°/45°/
## 45°), realistic walls are 2–3× the cardinal volume. Tractable.

## ---------- 6b. Pure-VM vs host-bridge ---------------------------
##
## Today's `forward N` rasterises one voxel per `begin_move` callback
## — fine for the candy cane (~120k voxels at speed = ASAP feels
## instant), but every voxel pays the VM↔host crossing cost. A
## `box(...)` that runs the whole AABB scan inside one bridge call
## should already win even for big rotated walls. So:
##
##   Phase 1: implement `box` entirely in VM Nim. The kernel is a
##            triple loop calling `draw_voxel` per cell. Validates
##            the API shape without committing to a host-side proc.
##
##   Phase 2 (only if profiling shows it matters): port the kernel
##            to host_bridge as e.g.
##              proc box_rasterise(self: Build,
##                                 t: Transform, size: Vector3,
##                                 pivot: Vector3, fill: bool,
##                                 color: Colors)
##            writing voxels directly into the chunk store, bypassing
##            per-cell `draw_voxel` overhead.
##
## Start with Phase 1. We can measure later.

## ---------- 6c. `sphere` and `cylinder` get the same treatment ----
##
## Both already centre-on-a-point and ignore turtle heading; the OBB
## machinery generalises trivially. `sphere` is direction-invariant
## so heading literally doesn't matter; `cylinder` would gain a
## "axis along the turtle's forward" mode if we want it (otherwise
## stays vertical-by-default).
##
## Not exploring further here — solving `box` first.

## ---------- 6d. Implementation step list --------------------------
##
##   1. Add `WorldBox` type + helpers (`size`, `centre`, `contains`,
##      `intersects`, `expanded`, `at`, `from`, `around`) in
##      vmlib/enu and the matching host-side type if needed.
##
##   2. Implement `box(...)` in VM Nim with the OBB scan-converter.
##      Cardinal fast-path optional but cheap to add (basis ≈
##      identity → skip the inverse + range test, do today's
##      fill_box loop).
##
##   3. Update `place` / `fill_sphere` / `fill_cylinder` to take the
##      same `at` / `pivot` / `from` parameter shape for consistency.
##      Keep the old names as deprecated aliases for one release if
##      we want a soft migration, otherwise rip out and update the
##      skill docs in lockstep.
##
##   4. Implement `wall(length, height = …)` and
##      `floor(length, width = length)` as one-line wrappers over
##      `box(..., pivot = corner)` + `forward length`.
##
##   5. Implement `bounds` / `proto_bounds` / `overlaps` / `fits` /
##      `clearance` (Section 4). The `proto_bounds` path needs the
##      voxel-tight AABB on a Build, which the OBB scan can produce
##      as a side effect during `box` calls (track min/max during
##      proto construction and cache as `proto_bbox`).
##
##   6. Rewrite the skill docs to use `box` / `wall` / `floor` and
##      the query API. Update `build_bungalow_compact.nim` as the
##      smoke test that the new primitives feel right.
