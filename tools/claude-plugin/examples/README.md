# Canned Examples

Verified, working scripts. Copy one into `scripts/build_<name>.nim`
(or `bot_<name>.nim` for the bot), add a matching data json, and adapt.
Each header comment says what the example teaches. Prototypes
(`name X`) and their spawners are separate files — never instantiate a
proto from its own script.

## Buildings & towers

| File | Teaches |
|---|---|
| `candy_tower.nim` | polygon walk + under-turn drift, cycle() stripes |
| `dna_tower.nim` | math-driven placement, structure around empty space |
| `scraper_monolith.nim` | hollow shells; restraint as a style |
| `scraper_twist.nim` | per-floor rotation, `pivot = centre` |
| `scraper_drill.nim` | solid-then-carve, windows, balcony floors |
| `scraper_orbs.nim` | sphere stacking, ground dome, eraser core, portholes |
| `scraper_setback.nim` | hollow tiers, window-grid proc, helper-proc reuse |
| `scraper_ziggurat.nim` | terraced massing, per-tier detail loops |
| `scraper_spires.nim` | fractional-size tapers (cones), fused organic massing |
| `pyramid.nim` | full-scale 1 m blocks — scale for fit, not detail |

## Castles & trees

| File | Teaches |
|---|---|
| `castle_fairytale.nim` | composing a scene from helper procs |
| `castle_citadel.nim` | ornate composition: merlons/tiers/towers reused everywhere |
| `spiral_tree.nim` + `tree_showcase.nim` | proto params + internal randomness; spawner pattern |
| `fractal_tree.nim` | recursion; the roll-then-pitch (L-system) branching move |
| `tower.nim` + `tower_cluster.nim` | minimal proto/spawner pair; randomised instances |

## Animated & interactive

| File | Teaches |
|---|---|
| `ufo.nim` | move-mode state machine: hysteresis, tether, glow |
| `door.nim` + `button.nim` + `doorway.nim` | cross-unit wiring; proto-object param defaults; pass `color` to `.new()` |
| `coin.nim` | Player.hit, show = false, duration-sleep idle |
| `dining_chair.nim` + `dining_table.nim` + `furniture_plaza.nim` | `anchor:` blocks; scaled protos; rotate-in-place |
| `bot_greeter.nim` | bot state machine, wander/tether, say with markdown sign |
| `sine_sculpture.nim` | save()/restore() fans; dashed drawing |
