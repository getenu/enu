# Loops — Level Spec (pilot)

> Pilot level + **spec template** for every concept level. Sections here
> (Concept · Theme · Challenge · Checker · Reward · Narration · Ambiance ·
> Features/gaps · Gating) are the per-level template referenced in
> `design.md` §8.

## Concept

**Repetition** with `N.times:` — "do this again and again without *writing* it
again and again." Builds on Sequence (tutorial-1: movement + `place`). The aha:
one short loop replaces a tall stack of identical lines.

## Theme

A **coastal harbor** at the edge of town. A tall striped **lighthouse** was
never finished — its tower is a stump and its lamp is dark, so boats can't find
the way in. Daytime, legible. Palette within Enu's 6 colors: `blue` sea,
`brown` dock + pilings + rock, `white`+`red` striped tower, `white` for the lit
lamp/beam, `black` for the dark (unlit) lamp.

The reward is unmistakable: the dark lamp turns bright **white**, a **beam**
reaches out over the water, and a little boat glides safely to the dock.

## The challenge (core, required)

The lighthouse ships **finished**: a `brown` rock base, a 1–2 block tower stub,
and a **floating target marker** (a ring/halo) at the goal height. The student
edits `build_lighthouse` to **stack the tower up to the marker with a loop**.

- Starter `scripts/build_lighthouse.nim`: the stub + a comment —
  `# Stack the tower up to the glowing ring. Try a loop!`
- **Target height = 10** (tall enough that hand-stacking is tedious, so the loop
  is the natural move — supports the method check being light-touch).
- Reference solution shape (turtle idiom, simplest):
  ```
  10.times:
    place(0, it, 0, white)   # or up()/forward in a turtle style — pick one idiom
  ```
  Final idiom chosen during the build; whichever reads most clearly for a 10yo.

## Checker (in-world, deterministic — no runtime agent)

A hidden `checker` unit polls in a `forever:` loop:

- **Result (primary):** `build_lighthouse` bounds **height ≥ TARGET** (and its
  footprint stays on the base). Settle-check via `pending_block_updates` /
  rendered count before judging.
- **Method (light touch):** the `build_lighthouse` source contains a loop
  (`.times` or `for`). Discourages hand-placing 10 blocks. **Drop this if clean
  source access turns out to be a gap** — result is primary.
- **Latch:** fire the reaction once, then stop re-firing.

## Reward / reaction (visible)

On pass: lamp blocks flip `black → white`, a `white` **beam** extends out over
the sea, a small boat glides to the dock, and the keeper says *"You did it —
that's a **loop**!"*. The reaction also **opens the path** to the next area
(gate/bridge) — the gating mechanic.

## Narration beats

1. **Keeper** (bot or sign) at the dock states the problem: lamp's dark, boats
   lost — *finish the tower*.
2. Minimal teach: one `times` example + "open `build_lighthouse` and stack it to
   the ring."
3. On success: celebrate and **name the concept** ("that's a loop!").

## Ambiance (mood-board: world1 at lower density)

Dock with a **row of pilings** (a colonnade — a repetition echo), a couple of
moored boats, crates, a cottage or two, rocks, gulls. **Legibility first:** a
clear sightline from spawn → keeper → lighthouse base → floating marker. Keep
≥ 5 m clear around spawn (0,0,0). Footprint well inside ±500.

## Required Enu features / gaps to confirm (this pilot's job)

- Read a build's **height/bounds from a checker** at runtime — confirm.
- **Script-source access** for the method check — confirm or note as a gap.
- A reusable **"goal met → reaction (+ latch)"** pattern — establish it here as
  the template other levels copy.

## Optional extras (nobody must do them)

- **Dock colonnade:** place a row of N pilings with a loop.
- **Spiral stair** inside the tower.
- A second, taller lighthouse / free-build dock.

## Gating

Core tower → reaction unlocks the next area. Extras + a nearby free-build dock
are optional.
