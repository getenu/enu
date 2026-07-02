# Loops — Level Spec (pilot, as built)

> Pilot level + **spec template** for every concept level. Sections here
> (Concept · Theme · Challenges · Checkers · Rewards · Narration · Ambiance ·
> Features/gaps · Gating) are the per-level template referenced in
> `design.md` §8. This version describes the level as **built and verified**
> (`share/worlds/course/loops`).

## Concept

**Repetition** with `N.times:` — "do this again and again without *writing* it
again and again." Builds on Sequence (movement + the editor). The aha: one
short loop replaces a tall stack of identical lines.

## Theme

**Loops Island** — a small coastal harbor: white-sand island in a calm blue
sea, one step up from the mainland meadow. A black road with a dashed
centerline (itself loop-drawn) runs from the spawn beach to an unfinished
lighthouse on a rock. Code-tool-only: `level.json` sets `show_tools: false`
and a hidden director unit adds back `CodeMode` and pre-selects it. No
building by hand, no bot placement.

## Teaching arc (hook → show → tell → play → exercises → extend)

1. **Hook** — Pip (blue bot) greets at spawn, names the three jobs.
2. **Show** — `build_demo`: a red/white spiral staircase builds itself slowly,
   pauses, erases, and rebuilds forever. You watch a loop work before it has
   a name.
3. **Tell** — the "What's a loop?" sign: jumping jacks, stir the pot, one
   `10.times:` example.
4. **Play** — the "You drive the loop" sign: `nim://` links stack 5/10/20
   blocks beside the signpost. Same loop, different count. (Needs an
   interactive click; not headless-verifiable.)
5. **Exercises** — three, distinct in shape (below).
6. **Extend** — the "Extra credit" sign near the lighthouse: pilings, taller
   tower, spiral stair, loop-inside-a-loop.

## The exercises

### 1. The lighthouse (core — gates the pier)

`build_lighthouse` (student stub, on the rock): one worked layer
(`box(3, 1, 3)`) + a comment pointing at `10.times:` and stripes via
`color = cycle(red, white)`. Reference solution:

```nim
10.times:
  color = cycle(red, white)
  box(3, 1, 3)
  up 1
```

**Checkers** (three independent units poll `bounds` height ≥ 10, each with
its own latch — decoupled and robust):
- `build_lamp` — the dark 3×3×3 lamp room turns white and a beam grows
  block-by-block out over the sea.
- `build_gate` — the harbor gate's doorway erases, opening the causeway to
  the pier ("Next stop: Variables!").
- `build_boat` — the lost boat sails home to the dock.

### 2. Salty's crossing (bot puzzle)

Salty (green bot) can't swim; the flag chest is across the channel.
`build_stones` (student stub at the water's edge, facing the far bank): one
stone (`box(2, 1, 2)`) + "repeat with a loop" (hint: `forward 4`). Reference:

```nim
6.times:
  box(2, 1, 2)
  forward 4
```

**Checker:** Salty himself — polls the stones' `bounds` span ≥ 20, then
walks across. Stones are *spaced*: he falls into each gap and climbs out
(the floor-follow), bumbling charmingly. `build_chest` polls Salty's
position past the bank and raises the green flag.

### 3. Art Beach (no obstacle — just make something cool)

`build_myart` (student stub): a small green square walk. The sign suggests a
color-cycling spiral and says "change every number." **Checker:**
`build_artsign` polls the art's bounds volume ≥ 60 (or height ≥ 8) and swaps
its title to "A masterpiece!". No gate, no stakes.

## Ambiance

Sea, channel, sand, dock, causeway, pier — all 1 block thick over the world
plane so nobody can fall anywhere they can't walk out of. Clear sightline
from spawn: road → rock → floating dark lamp.

## Lessons that fed the template (gaps found while building)

- **`bounds` is the reliable checker input.** `rendered_voxel_count` reads 0
  away from viewers (it counts *meshed* voxels — meshing is viewer-local).
- **Every build paints a default block at its origin on reset** — scene units
  keep their origins inside their drawn bodies or a stray cube appears.
- **Signs are single-sided**; turn the unit toward the approach before `say`.
  Turtle turns change the unit-local draw frame — draw first or keep shapes
  symmetric.
- **Guard `find_by_id` results for nil** — checkers can poll before their
  target loads.
- A wedged script (compile error) doesn't always hot-reload; a fresh launch
  clears it. `wait_for_script` forces a reload when iterating.
- TODO: no script API to disable flying; the level is designed so flight
  skips nothing. `player.playing = true` changes too much.

## Gating

Lighthouse (core) → gate opens → pier → next level (Variables) when it
exists. Salty + Art Beach are optional; nobody must do everything.
