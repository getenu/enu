# Instance bounding-box / clearance query API — design sketch

The recurring TODO across the skills: scripts placing scaled, rotated
prototype instances have to hand-compute each one's footprint and
mentally track overlap against walls, doors, and other instances. The
underlying voxel data and transforms already exist; this proposal
exposes them as queries so authors (and humans, via MCP `eval`) can
ask the engine instead.

This is a sketch for the user to react to. Concrete primitives and
usage shapes only; the implementation pass comes after the API shape
is agreed.

## What scripts actually want to ask

These are the questions that come up over and over while building:

1. **"Where exactly is this thing in the world?"** — given an instance,
   what world-space box does it occupy (after scale + rotation +
   anchor)?
2. **"Will this collide if I place it here?"** — would a proposed new
   instance / move overlap an existing build or instance?
3. **"What's blocking this doorway / hallway?"** — given a corridor or
   clearance volume, list the instances inside it.
4. **"Is there enough room for the player to walk between these two?"**
   — distance between two instances' nearest surfaces.

## Proposed primitives

```nim
type
  WorldBox* = object
    min*, max*: Vector3      # world-space AABB

proc bounds*(self: Unit): WorldBox
  ## Tight world-space AABB after scale, rotation, and anchor are
  ## applied. For Builds this is the voxel bounding box transformed
  ## into world coords. For Bots/Players, the unit's collider AABB.

proc overlaps*(a, b: Unit): bool
  ## True if `a.bounds` and `b.bounds` intersect.

proc clearance*(self: Unit, others: seq[Unit] = @[]): float
  ## Shortest distance from the unit's surface to the nearest other
  ## unit's surface (or world voxel). 0 means touching; negative means
  ## interpenetrating. `others` defaults to all units in the current
  ## level except `self`.

proc fits*(box: WorldBox): bool
  ## True if `box` is free of voxels (any Build's voxel data) and
  ## doesn't intersect any instance's bounds. Use to validate a
  ## proposed placement.
```

And two helpers on `WorldBox` because every caller will want them:

```nim
proc size*(b: WorldBox): Vector3
proc centre*(b: WorldBox): Vector3
proc contains*(b: WorldBox, p: Vector3): bool
proc intersects*(a, b: WorldBox): bool
proc expanded*(b: WorldBox, margin: float): WorldBox
  ## `box.expanded(1.0)` for a "1m clearance" version of the box.
```

`bounds` returns an AABB (cheap, conservative). If we ever need OBB
precision (a chair rotated 45° has a much smaller AABB than the bbox
of its rotated corners), that's a follow-up primitive — the AABB
covers ~95% of real placement-validation work.

## Usage examples

### A. Validate a chair placement before committing

```nim
let proposed = DiningChair.proto_bounds(
  position = vec3(4.5, 1, -103.25), rotation = 0
)
if proposed.fits():
  DiningChair.new(position = vec3(4.5, 1, -103.25), rotation = 0)
else:
  echo "won't fit — collides with: ", proposed.what_blocks()
```

(`proto_bounds` is a class-method on protos: compute the would-be
bounds without actually instantiating. `what_blocks` is an optional
debug helper that returns the colliding units.)

### B. Walk a corridor and ask if anything's in the way

```nim
let doorway = WorldBox(min: vec3(8, 1, 16), max: vec3(9, 3, 16.5))
let clear_path = doorway.expanded(0.5)   # half-metre approach margin
for unit in units_in_box(clear_path):
  echo "blocking doorway: ", unit.id
```

(`units_in_box` today filters by origin. New semantics: a unit is in
the box if its bounds intersect it. Keeps the obvious name, breaks
existing scripts that relied on origin-only — fine, we'll refresh the
skills along with this work.)

### C. Auto-arrange chairs around a table (using bounds)

```nim
let table = DiningTable.new(position = vec3(3.5, 1, -104.5))
let tb = table.bounds
let chair_w = 0.5   # known DiningChair footprint at scale 0.25

# Place a chair at each of the four cardinal mid-edges, snug to the
# table's bounds, facing inward.
DiningChair.new(
  position = vec3(tb.centre.x, 1, tb.min.z - chair_w / 2),
  rotation = 0
)
DiningChair.new(
  position = vec3(tb.centre.x, 1, tb.max.z + chair_w / 2),
  rotation = 180
)
# ...etc.
```

The author no longer has to know the table is 2 m × 1.25 m or worry
about which edge the proto's local-(0,0,0) sits on — `bounds.centre`
and `bounds.min/max` are stable.

### D. Walk-through verification in /reload-verify

```nim
# After building a room, check every doorway has clearance
for door in doorways:
  let box = WorldBox(
    min: door.position - vec3(0.5, 0, 0.5),
    max: door.position + vec3(0.5, 3, 0.5)
  )
  if not fits(box):
    echo "doorway ", door.position, " is blocked"
```

### E. Player-facing clearance check

```nim
let me = Player.first
for inst in [chair1, chair2, table, sofa]:
  if me.bounds.intersects(inst.bounds):
    echo "you're clipping ", inst.id
```

### F. MCP-side: ask "what's in the master bedroom"

```nim
# eval'd from MCP:
let bedroom = WorldBox(min: vec3(3, 0, -116), max: vec3(8, 5, -111))
for u in units_in_box(bedroom):
  echo u.id, " bounds=", u.bounds
```

## Open questions before implementing

- **AABB or OBB**: AABB is dead simple and good enough for grid-aligned
  cardinal-rotation placement (the common case). OBB matters more for
  arbitrary angles. Start AABB, add OBB later if needed?
- **Voxel-aware vs. proto-AABB**: a `Build` is a sparse voxel cloud;
  its AABB is conservative (lots of empty space inside an L-shaped
  wall). Should `bounds` return the voxel-tight AABB (recomputed when
  the build changes) or just the proto's declared bounds? The existing
  `bounds_value: EdValue[AABB]` field on `Build` (`src/types.nim:306`)
  suggests we already track something — verify what's in there.
- **Cost of `clearance`**: requires scanning all units. Fine for
  per-placement validation, expensive for per-frame use. Document the
  cost, don't try to make it free.
- **`proto_bounds` without instantiating**: needs a way to ask the
  proto "if I called .new with these args, what would the bounds be?"
  Either (a) the proto declares its bbox statically (author tells us),
  or (b) we instantiate-then-destroy to measure. (a) is cheaper but
  needs an authoring convention; (b) is automatic but wasteful.
- **Should the anchor offset show up in `bounds`?** The anchor only
  changes the *pivot*, not the voxel extents — but it does change
  where `position` places the voxel cloud. As long as we compute
  bounds in world coords after composing the full transform, anchor
  falls out for free.

## Out of scope

- Continuous collision response (this is a query API, not a physics
  engine).
- Spatial indexing / acceleration structures. Start with linear scans
  over units; revisit if profiling shows it matters.
- UI display of bounding boxes in-game (debug overlay would be nice
  but it's a separate piece).
