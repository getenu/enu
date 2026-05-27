# `anchor:` block — design notes

Captured from chat exploration; needs a real plan + implementation pass.

## Problem

Today a unit's pivot point — what `position` places, what `rotation`
spins around, what `forward` moves along in `move` mode — is the unit's
local `(0, 0, 0)`, which is the first voxel placed.

For human-built units this is fine: people place their first block where
they want the pivot, often building middle-out specifically because it's
the only way to control the anchor.

For scripts using `fill_box(0, 0, 0, ...)` the first voxel is always one
corner of the bounding box, so the anchor sits in a corner. Rotating the
instance then swings it around that corner instead of pivoting in place,
and `position = vec3(...)` places the corner — not the centre — at the
world coord. Workarounds today:

- Draw the proto around `(0, 0, 0)` with negative voxel coords (the
  "centred proto" pattern in `/build-script`)
- Per-instance position arithmetic to compensate for rotation pivot

Both are workarounds for the underlying API gap.

Direction matters for the same reason. `move me; forward 10` moves the
unit along its local `-Z` axis; if the unit was drawn facing east in
proto-local coords (turtle ended up going `+X`), `forward` in move mode
moves it the "wrong" way relative to how it looks.

## Proposal

A first-class anchor concept on every unit, set declaratively via a
turtle-driven block:

```nim
# At the top of a build script. Runs before any voxels appear because
# units are invisible until first script yield.
anchor:
  forward 2
  up 1
  turn right

# Now draw normally. (0, 0, 0) is still the first block placed;
# `anchor` is an offset declared relative to it.
fill_box(0, 0, 0, 4, 0, 4, brown)
# ...
```

The block captures two things from the turtle when it exits:

- **End position** → the unit's pivot / placement point. `position`
  places this point at the world coord. `rotation` pivots around it.
- **End direction** → the unit's intrinsic forward. `forward` in
  `move` mode (and the future `move other_unit`) translates the unit
  along this direction, regardless of how voxels were drawn.

Anchor is a 6-DOF pose. Both components have to be exposed for the
direction half to be useful.

## Block semantics

- **Starting pose:** turtle at proto-local `(0, 0, 0)` facing `-Z`
  (the Logo default). Independent of any prior turtle state in the
  script. Predictable; the block doesn't depend on script ordering.
- **No drawing inside the block.** Voxels are not placed even if
  `drawing = true` outside. Force `drawing = false` for the block's
  duration; restore after. Authors should not have to remember a
  toggle.
- **No turtle state leak.** The pre-block turtle position and
  direction are restored when the block exits. Only the unit's anchor
  field is updated. Same reasoning as not drawing.
- **No suspending.** A new "set anchor" mode for `begin_move` /
  `begin_turn` that executes geometry immediately and returns,
  accumulating final pose. This mirrors the existing `move` vs `build`
  mode distinction.
- **Set anchor before first yield.** Document the convention; consider
  warning if anchor is set after the unit has been rendered for a
  frame. The "unit invisible until first yield" rule is what makes
  this safe — re-anchoring after the unit appears visibly moves it,
  which is correct behaviour but should be a deliberate action, not a
  side effect of "I put my anchor declaration too far down."
- **Turtle commands only inside the block.** `forward`, `right`,
  `up`, `back`, `left`, `down`, `turn`. Not `draw_position = ...`.
  Keeps the block in one paradigm.

## Live re-anchoring on instances

The block form works on instances too, with the same syntax:

```nim
let chair = DiningChair.new(...)
chair.anchor:
  forward 5
  up 1
```

This visibly moves and reorients the chair (because the unit is
already on screen by this point). Correct behaviour; it's also what
the future "drag anchor in the UI" tool will do.

## Interaction with existing primitives

- **`position`** places the anchor at the given world coord.
  Side effect: changing the anchor on a visible unit moves the unit
  (the anchor stays anchored at the unit's current `position`).
- **`rotation`** pivots around the anchor (today: yaw around world
  Y; the pivot point is the anchor's position).
- **`scale`** scales around the anchor.
- **`forward` / `right` / `up` in `move` mode** translate the unit
  along the anchor's direction frame (so the unit's intrinsic
  "forward" is the anchor's forward, not proto-local `-Z`).

## What about `bake`?

Considered: a sibling `bake` mode that rewrites the unit's voxel data
to bake a rotation into the voxels and zero the runtime rotation.
Rejected because it's non-idempotent — running the script twice would
rotate twice. `anchor: turn right` does the same job declaratively:
the unit appears and behaves as though it had been drawn rotated 90°,
and re-running the script produces the same result every time.

## Future: JSON persistence

When the UI grows a "set anchor here" tool, the human's choice should
persist as a property in the unit's JSON. Applied before the script
runs.

Open: if a script also has an `anchor:` block, does it **replace** the
JSON anchor or **compose** on top of it? Probably compose — JSON
encodes "the human placed the anchor here" and the script can adjust
from there — with a flag on the JSON form for "hard human preference,
scripts cannot override."

## Implementation hints (from chat)

- `begin_move` and `begin_turn` are the primitives most turtle API
  commands route through.
- They already take a mode parameter distinguishing `move` mode from
  `build` mode. Add a `set_anchor` mode.
- In `set_anchor` mode, commands execute their geometry but don't
  suspend and don't move/draw the unit. They just accumulate the
  effective pose.
- The `anchor:` block enters `set_anchor` mode for its duration,
  resets pre-block turtle state on exit, writes the accumulated pose
  to the unit's anchor field.

## Open questions

- Storage: is the anchor a field on `Unit` (host-side) plus an EdValue
  for sync? Probably yes, mirrors `transform_value`.
- Naming: `anchor` vs `pivot` vs `origin`. `anchor` reads cleanly in
  both static placement and animation contexts.
- Should the anchor default change for new units (currently
  `(0, 0, 0)`, the first-voxel point)? Probably no — backwards-
  compatible. Authors opt in by writing `anchor:` blocks.
- Default-anchor for scripted protos that draw with `fill_box(0, ...)`:
  worth a sensible default that's "centre of bbox at script-yield
  time"? Or leave to the script author to declare. Probably the
  latter, with a clear convention documented in `/build-script`.
- Interaction with `start_transform` in the JSON: anchor is in
  proto-local coords, separate from the world transform. They compose
  cleanly.
- Animation: future `spin around the anchor's vertical axis` is a
  natural primitive once the pose is captured. Out of scope here but
  worth knowing the slot exists.

## Skill / docs updates implied

- `/build-script` "Designing protos for rotation" section gets a
  rewrite: stop telling authors to draw around `(0, 0, 0)` with
  negative coords, point them at `anchor:` instead.
- `/build-plan` Inventory column for anchor (and probably the open
  TODO about bounding-box queries — anchor pins down the reference
  point for that query).
- `/build-structure` proto-size table's "Origin" column becomes
  meaningless once anchor exists; replace with "Anchor" recipe per
  proto (or drop the column and reference the anchor pattern from
  `/build-script`).
