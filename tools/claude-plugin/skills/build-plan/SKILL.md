---
description: Plan multi-unit Enu builds before placing voxels. Use for multi-room buildings, multi-structure layouts, or any build with more than ~3 units.
---

# Plan Before Building

Multi-room buildings, multi-structure layouts, and any build with more than
~3 units don't survive piece-by-piece freestyling. Layout a plan first, then
execute against it.

> **Why this is `/build-plan` and not `/plan`:** Claude Code has a built-in
> `/plan` command that activates plan mode; a skill named `plan` is shadowed
> by it. Use `/build-plan` to invoke this skill.

## Usage

```
/build-plan <description>
```

## Output

A markdown plan file at `<level_dir>/plan.md` (or appended to it). Each plan
section is self-contained: someone reading just that section should be able
to act on it without scrolling.

## Structure

```markdown
# <Project Name>

## Goal

One paragraph. What the user asked for, in concrete terms.

## Layout

Coordinate system reminder + a text sketch.

\`\`\`
       -Z (north)
        ↑
        |
  -X ←──┼──→ +X
        |
        ↓
       +Z (south)
\`\`\`

**Stay on the ground.** The ground is a 1000×1000 plane centred on the
origin: solid floor from x/z = -500 to +500, surface at y = 0. Keep every
build's *full footprint* (not just its origin) inside ±500 with a margin —
a build whose extent crosses -500 hangs half-off into the void. Place
origins at **y = 0** so the lowest voxel rests on the ground (y = 1 floats
the build 1 m up).

**Keep the spawn clear.** The player spawns at (0, 0, 0); leave at least
5 m of open ground in every direction around it.

Top-down ASCII for the major structures, with coordinates marked. Use a
grid scale that fits (e.g. 1 char = 5 voxels):

\`\`\`
              z=-20 ─────────────────────────
                    │ N wall          │
              z=-30 │     [castle    ]│  walls 49 wide
              z=-65 │  S wall (gate) │
                    └─────────────────┘
              z=-100      [castle_main keep]
\`\`\`

## Inventory

What gets built, with sizes and positions:

| Unit | Position (origin) | Footprint (m) | Notes |
|------|-------------------|---------------|-------|
| `build_castle_outer_wall` | (0, 0, -20) → (0, 0, -65) | 49 × 6 × 45 | uses Wall proto |
| `build_keep` | (-12, 0, -120) | 24 × 25 × 20 | main building |
| `BedQueen` instance #1 | (4, 0, -116) | 2 × 0.5 × 3 (after scale 0.25) | master bedroom |
| ... |

**Always include the world-space footprint** (extent in metres) for scaled
prototype instances — see the *Scale math* section below.

## Dependencies

Things that must exist before others, in order:

1. Outer walls (perimeter + corners)
2. Floor/courtyard
3. Inner buildings (keep, towers)
4. Furniture protos (must be defined before any `.new` call references them)
5. Decorations (torches, banners, signs)

## Clearance & Walkability

> **The 1 m rule:** every furniture piece needs ≥ 1 m of clear space from
> walls and other objects, *except* the wall a headboard / counter / back of
> sofa naturally rests against. A queen bed wedged into a 3 m room with the
> headboard and footboard both touching walls reads as "wrong" — it doesn't
> matter that the dimensions are technically realistic.

> **Doors are choke points.** Walking-through clearance is non-negotiable:
> – 2 voxels wide × 3 tall is the minimum interior door
> – Hallways should be ≥ 2 voxels deep (1-deep hallways feel claustrophobic)
> – Nothing inside the room should be within 2 voxels of a doorway in the
>   axis perpendicular to the wall (otherwise you walk into a chair / counter
>   / table immediately on entry)

Before declaring done, **mentally walk through every door from both sides**
and confirm there's no piece of furniture in the entry path. This catches
more bugs than screenshots do.

## Verification Plan

How will I know each phase worked?

- After perimeter: `find_voxel_overlaps` clean for the walls
- After floor: top-down screenshot shows enclosed shape
- After buildings: `for u in units_in_box(-25,0,-65, 25,30,-20): echo u.id` shows expected list
- **Walk-through pass**: have the human (or `screenshot_from_player`) walk
  through every door — confirm passable, no clipping, furniture readable
  from inside

## Open Questions

Anything I'm unsure of — confirm with the human before acting:

- Should the keep have multiple floors? Default yes.
- East/West sides — does the gate face N or S? Assuming N.
- ...
```

## When to write a plan

- Multi-room/multi-floor buildings
- Anything with 5+ units
- Anywhere you'll be referring back to "where was that thing again"
- When the human says "build a castle/city/dungeon/forest" without precise coordinates

## When NOT to write a plan

- Single placements ("put a torch at (5, 1, -10)")
- Bugfix passes (just fix what the human pointed at)
- Cosmetic tweaks to existing layouts

## Plan → Implementation Loop

1. Write the plan
2. Read it back, look for layout mistakes (overlapping coordinates, missing
   corners, etc.). Use `box_is_free` (or `units_overlapping` for the list)
   to verify nothing already occupies the target space.
3. **Confirm with the human** before laying any voxels. The plan is cheap to
   change; the world is expensive.
4. Build phase 1, screenshot, **walk through**, update plan with "✓" or notes.
5. Repeat phases.
6. When done, leave the plan as documentation (don't delete it). Future
   sessions can pick up where this one left off.

### Dispatching subagents

Plan sections should be executable verbatim — explicit coordinates and
complete scripts — so they can be handed to parallel subagents, each
passing its own `agent_id` for its own bot. Prefer **Sonnet** for
well-specified build sections and **Opus** for sections needing design
judgment or debugging; keep verification (bounds checks, screenshots,
walk-throughs) with the orchestrator.

## Furniture and 1:1 voxel readability

**1 m³ voxels read as Tetris blocks, not objects.** A "chair" made from a
single cube is a cube; three cubes in a row is not a couch. Only things that
*really are* boxy at human scale read at 1:1:

- Kitchen counter (typical real depth ≈ 1 m) ✓
- Fridge ✓
- Stove top ✓
- Dresser (narrow ones) ✓
- Sign on a wall ✓

Everything else needs a **scaled prototype** — a separate build prototype
defined at higher internal voxel resolution with `scale = 0.25` or similar,
then instantiated via `.new(...)`. See `/build-script` for the prototype
mechanism.

Examples (not an exhaustive catalog — design new protos as your build
needs them):

- `BedQueen`, `BedTwin` — frame, mattress, headboard, pillows, blanket
- `Sofa` — base, cushions, back, arms
- `DiningTable` — tabletop slab + 4 corner legs
- `DiningChair` — seat + 4 legs + backrest
- `Toilet`, `Bathtub` — bathroom fixtures

If the build the human asks for needs a `CoffeeTable`, `Lamp`, `Bookshelf`,
`Workbench`, etc., create new protos for them — don't try to render them
as 1:1 voxel cubes.

### Scale math

Each prototype draws voxels in its own local coords. With `scale = 0.25`:

- A `box(width = 8, height = 1, depth = 12, …)` covers 8 voxels wide
  along the proto's +X and 12 voxels deep along its -Z.
- The instance footprint in world units is `voxel_count × scale`:
  8 × 0.25 = **2 m wide**, 12 × 0.25 = **3 m deep**.
- An instance placed at `position = vec3(X, Y, Z)` occupies
  `(X..X+2, Y..Y+0.5, Z..Z+3)`. By default the proto's local
  `(0, 0, 0)` is the NW-bottom corner — *not* the centre — of the
  displayed object. A proto with an `anchor:` block reports its
  declared pivot point at `position` instead; use the anchor pose to
  reason about footprints in that case.

To place a queen bed against the north wall of a 5 m × 5 m bedroom (world
`x = 3..8`, `z = −116..−111`):

- Bed footprint: 2 × 0.5 × 3
- Headboard at `z = -116` (north wall) means `position.z = -116`
- Centring the bed in the 5 m wide room: bed origin `x = 4`
  (bed extends `4..6`, leaves 1 m clearance on east, 1 m on west)
- Final: `BedQueen.new(position = vec3(4, 0, -116))`

Check clearance before placing with the bounds queries:
`box_is_free(DiningChair.bounds_at(vec3(4, 0, -103), rotation = 90))`
predicts the world AABB of a hypothetical instance; `unit.bounds`,
`a.overlaps(b)`, and `units_overlapping(box)` cover already-placed
units. Still list each instance's footprint in the Inventory table —
the plan should be checkable on paper — and verify by walk-through
after building.

Rotation is a built-in `.new(...)` parameter and a mutable instance
field — pass `rotation = 90` to spawn rotated, or assign
`inst.rotation = 90` after. For a proto that needs to rotate cleanly
in place (chairs around a table, etc.) declare an `anchor:` block in
the proto so `position` places the pivot and `rotation` spins around
it without half-extent offset arithmetic in the call site. See
`/build-script`.

## Sizing rooms for human feel

Real-life dimensions feel cramped through a flat-screen camera. For
interiors that read as "a normal room" when you walk into them, scale
1.5–2× larger than reality:

- Bedroom: 5–6 m on the long side, not 4
- Ceiling: 4 m, not 2.5 m (3 m is the minimum)
- Door: 2 m wide × 3 m tall (a 1 m doorway is functionally tight even
  though it matches real homes)

## Updating an existing plan

If `plan.md` exists, append a new section (`## <Date> — <change>`) rather
than rewriting. The plan is a history of decisions, not a final document.
