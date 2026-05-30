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
  WorldBox* = tuple[min, max: Vector3]   # world-space AABB

proc bounds*(self: Unit): WorldBox
  ## Tight world-space voxel AABB after scale, rotation, and anchor
  ## are applied. For Builds this is the tight bounding box of the
  ## actual placed voxels, transformed into world coords. For
  ## Bots/Players, the unit's collider AABB. Equally valid on a proto
  ## (`DiningChair.bounds`) and on an instance — a proto's bounds is
  ## the bounding box of whatever its draw script lays down.

proc overlaps*(a, b: Unit): bool
  ## True if `a.bounds` and `b.bounds` intersect.

proc clearance*(self: Unit): float
proc clearance*(self: Unit, others: seq[Unit]): float
  ## Shortest distance from the unit's surface to the nearest other
  ## unit's surface (or world voxel). 0 means touching; negative means
  ## interpenetrating. With no `others` argument, scans every other
  ## unit in the level.

proc box_is_free*(box: WorldBox): bool
  ## True if `box` is free of voxels (any Build's voxel data) AND
  ## doesn't intersect any instance's bounds. Contrast with the
  ## existing `clear_box` which checks voxels only.

proc what_blocks*(_: type WorldBox, box: WorldBox): seq[Unit]
  ## `WorldBox.what_blocks(box)` — units whose bounds intersect `box`.
  ## Same data as `units_overlapping(box)`, framed for the "why did
  ## `box_is_free` say no?" debug call site.

proc units_overlapping*(box: WorldBox): seq[Unit]
  ## Units whose bounds intersect `box`. New shape; the existing
  ## `units_in_box(x1..z2)` keeps its origin-in-box semantics for
  ## back-compat (and as the MCP-eval-friendly entry that formats
  ## a string).
```

And helpers on `WorldBox` because every caller will want them:

```nim
proc size*(b: WorldBox): Vector3
proc centre*(b: WorldBox): Vector3
proc contains*(b: WorldBox, p: Vector3): bool  # auto-enables `p in b`
proc intersects*(a, b: WorldBox): bool
proc expanded*(b: WorldBox, margin: float): WorldBox
  ## `box.expanded(1.0)` for a "1m clearance" version of the box.
```

`bounds` returns an AABB (cheap, conservative). If we ever need OBB
precision (a chair rotated 45° has a much smaller AABB than the bbox
of its rotated corners), that's a follow-up primitive — the AABB
covers ~95% of real placement-validation work.

### Naming note: `bounds` vs the existing field

Today, `Build` has an internal `bounds_value: EdValue[AABB]` field
holding a chunk-aligned local-space AABB (used by VoxelTerrain for
culling). That's not what user code wants. Plan:

- Rename the existing field → `chunk_bounds_value` (and `self.bounds`
  internal accessor → `self.chunk_bounds`).
- Add a new tight voxel-AABB field maintained per-build, exposed as
  the bridged `bounds` getter on `Unit`.

## Usage examples

### A. Validate a chair placement before committing

```nim
# `DiningChair.bounds` is the proto's voxel AABB at its declared
# position (defaults to origin). Shift it into the candidate spot:
let proto = DiningChair.bounds
let offset = vec3(4.5, 1, -103.25) - proto.min
let proposed: WorldBox = (proto.min + offset, proto.max + offset)
if box_is_free(proposed):
  DiningChair.new(position = vec3(4.5, 1, -103.25), rotation = 0)
else:
  echo "won't fit — collides with: ", WorldBox.what_blocks(proposed)
```

Rotation is harder to model without a real instance — for that case,
spawn → measure → destroy (`show = false; reset(clear = true)`)
is the documented workaround until OBB or a dedicated
`bounds_at(position, rotation)` primitive lands.

### B. Walk a corridor and ask if anything's in the way

```nim
let doorway: WorldBox = (vec3(8, 1, 16), vec3(9, 3, 16.5))
let clear_path = doorway.expanded(0.5)   # half-metre approach margin
for unit in units_overlapping(clear_path):
  echo "blocking doorway: ", unit.id
```

`units_overlapping` is the new primitive; the existing
`units_in_box(x1..z2)` keeps its origin-in-box semantics for
back-compat and for MCP-eval-friendly string output.

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
  let box: WorldBox = (
    door.position - vec3(0.5, 0, 0.5),
    door.position + vec3(0.5, 3, 0.5)
  )
  if not box_is_free(box):
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
let bedroom: WorldBox = (vec3(3, 0, -116), vec3(8, 5, -111))
for u in units_overlapping(bedroom):
  echo u.id, " bounds=", u.bounds
```

## Open questions before implementing

- **AABB or OBB**: AABB is dead simple and good enough for grid-aligned
  cardinal-rotation placement (the common case). OBB matters more for
  arbitrary angles. Start AABB, add OBB later if needed?
- **Voxel-aware bounds — decided**: `bounds` is voxel-tight. The
  existing chunk-aligned `bounds_value` gets renamed to
  `chunk_bounds_value` (it stays around for VoxelTerrain culling);
  a parallel tight-AABB field is added to `Build` and maintained as
  voxels are drawn / erased.
- **`bounds` on a proto vs an instance — decided**: same proc, same
  return type. A proto draws its voxels into itself (just with
  `show = false`) so `DiningChair.bounds` returns the tight world
  AABB of the proto's drawn voxels. No `proto_bounds` needed.
  *Implementation note*: today protos `quit()` before drawing in the
  documented pattern (`if not is_instance: show = false; quit()`).
  Either change the pattern (proto draws but hides) or add a
  draw-into-buffer measurement path. Resolve at implementation time.
- **Cost of `clearance`**: requires scanning all units. Fine for
  per-placement validation, expensive for per-frame use. Document the
  cost, don't try to make it free.
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
