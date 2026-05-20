# Plan Before Building

Multi-room buildings, multi-structure layouts, and any build with more than
~3 units don't survive piece-by-piece freestyling. Layout a plan first, then
execute against it.

## Usage

```
/plan <description>
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

```
       -Z (north)
        ↑
        |
  -X ←──┼──→ +X
        |
        ↓
       +Z (south)
```

Top-down ASCII for the major structures, with coordinates marked. Use a
grid scale that fits (e.g. 1 char = 5 voxels):

```
              z=-20 ─────────────────────────
                    │ N wall          │
              z=-30 │     [castle    ]│  walls 49 wide
              z=-65 │  S wall (gate) │
                    └─────────────────┘
              z=-100      [castle_main keep]
```

## Inventory

What gets built, with sizes and positions:

| Unit | Position | Size | Notes |
|------|----------|------|-------|
| `build_castle_outer_wall` | (0, 1, -20) → (0, 1, -65) | 49×6×45 | uses Wall proto |
| `build_keep` | (-12, 0, -120) | 24×25×20 | main building |
| ... |

## Dependencies

Things that must exist before others, in order:

1. Outer walls (perimeter + corners)
2. Floor/courtyard
3. Inner buildings (keep, towers)
4. Decorations (torches, banners, signs)

## Verification Plan

How will I know each phase worked?

- After perimeter: `find_voxel_overlaps` clean for the walls
- After floor: top-down screenshot shows enclosed shape
- After buildings: `units_in_box(-25,0,-65, 25,30,-20)` shows expected list

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
   corners, etc.). Use `units_in_box` to verify nothing already occupies the
   target space.
3. **Confirm with the human** before laying any voxels. The plan is cheap to
   change; the world is expensive.
4. Build phase 1, screenshot, update plan with "✓" or notes.
5. Repeat phases.
6. When done, leave the plan as documentation (don't delete it). Future
   sessions can pick up where this one left off.

## Updating an existing plan

If `plan.md` exists, append a new section (`## <Date> — <change>`) rather
than rewriting. The plan is a history of decisions, not a final document.
