# Course Exercise Bank (brainstorm)

Output of a 3-agent brainstorm + synthesis. Goal: **overproduce** world-grounded
exercise ideas, then pull gems for the multi-agent build-out.

**Core principle:** the goal is something the player physically *needs* in the
world (cross a gap, climb to a ledge, light a path), and the concept is genuinely
*required*. A plain "tower N tall" fails — one command (`up N`) does it. Loops
must repeat a *sequence* (stairs, spiral) or *spaced* items (stones, torches), or
drive a *behavior* (a shuttling platform), that no single primitive expresses.

**Turtle-first**: teach `forward/back/up/down/left/right`, `turn`, `box/sphere/
cylinder`, not `place(x,y,z)` coordinates.

---

## Recommended Loops exercises to prototype first

Lead with **build-to-unlock** — strictly loop-required, no physics risk, and they
reuse the already-proven `build_lamp.nim` checker (poll `Build.all` → read
`bounds`/count → latch → reward):

1. ⭐ **Stepping-stones across water** — `6.times: box(2,1,2,white); forward 3`.
   Spaced stones (gaps) can't be made by any single primitive → *strictly* needs
   the loop. Win = player reaches the far bank.
2. ⭐ **Extending bridge** — `12.times: box(2,1,3,brown); forward 3`. The loop
   literally lays the way across; checker reads `build.bounds.max.z` reaching the
   far edge. Cleanest "the loop *is* the path."
3. **Staircase / spiral ramp to a ledge** — `8.times: box(2,1,2); forward 1; up 1`
   (+ `turn` for a coiling ramp). Climb to reach the next section. Closest to the
   proven height-check.
4. **Dark-tunnel torches** — `8.times: forward 4; up 2; sphere(1,red); down 2`.
   Spaced torches light the path; the end door opens.

Pick 2–3, build them well, keep the best. Overproduce variants.

## The one feasibility question gating *traversal*

The moving-mechanism ideas (ferry, elevator, conveyor, drawbridge) are very
"alive" but **all depend on one unverified question: does a player/bot *ride* a
`move me` platform, or slide off / get left behind?** Working assumption (our +
the agents' consensus): bots do **not** auto-ride — they'd need a lip and/or
syncing the rider's position to the platform each tick.

**Verify with a clean in-Enu test before building any ferry/elevator exercise.**
Fallbacks if it doesn't work: player-rides (lower risk than bots), a position-sync
helper on the platform, or just favor build-to-unlock. (A first scripted test was
inconclusive — JSON-escaping snag, not an Enu result.)

## Two checker patterns cover almost everything

- **Position threshold** — player/bot crosses a z/y line, or `units_near(goal,
  r)` counts ≥ N.
- **Build measure** — a build's `bounds` (height / footprint length) or
  `rendered_voxel_count` reaches a target. Best for "the structure itself is the
  proof."

Both copy `build_lamp.nim`: `forever:` poll → latch a bool → fire the reward
(open a `Door`, swap a dark box to white + draw a beam — `door.nim` pattern).

## "Strictly loop-required" trick

**Spaced items with gaps** (stones, torches, pillars, rail sleepers) or
**per-iteration variation** (`cycle(red,white)` stripes, a taper) defeat the
one-shot primitives (`wall`/`floor`/`box`/`forward`). Lead graded challenges with
these so `up N` / `floor` can't shortcut them.

---

## Full idea bank

### Loops — traversal & moving mechanisms (needs the riding verdict)
- ⭐ Ferry/barge across a chasm (`move me; forever: forward N; sleep; back N; sleep`).
- ⭐ Extending bridge (loop *builds* the span — no riding needed; see above).
- Elevator platform (vertical shuttle to a high doorway).
- Drawbridge (rotate a span down — also needs "rotate while ridden" verified;
  translate-only "lift-bridge" fallback works now).
- Conveyor of stepping pads over lava (sideways shuttle; teaches `left`/`right`).
- Bot-ferry: send N bots across; win = N bots in the far zone (riskiest — bot
  riding; ferry-with-player is the fallback).
- Pendulum/swinging log; ski-lift/paternoster (single-car = a diagonal elevator).

### Loops — build / repair to unlock (safest; reuse build_lamp checker)
- ⭐ Stepping-stones with gaps; ⭐ dark-tunnel torches; collapsed footbridge;
  staircase to a ledge; drawbridge *ramp*; fill-the-pit (use a **checkerboard**
  variant so `floor` can't shortcut it); colonnade of N pillars holds a roof;
  beanstalk spiral to a floating island; lay railway track (spaced sleepers) +
  a `move me` cart; sandbag the flood (striped-brick wall so `wall` can't shortcut).

### Other concepts — seeds for the later levels
- **Variables (#3):** ⭐ Adjustable bridge — sign reads `GAP = N`; `floor(length =
  span, ...)`; *re-roll the gap between attempts so copy-paste fails*. Match-the-
  marker height. One-variable-used-twice ramp (run = 2×rise).
- **Nested loops (#4):** ⭐ Orchard 5×5 (loop-in-loop = grid). Checkerboard plaza
  (bridges into conditionals). Pyramid (inner range depends on outer index). Wall
  of windows (eraser grid on a vertical face).
- **Conditionals (#5):** ⭐ Altitude painter (color blocks by height with
  `if/elif/else`). Wall-following bot (turn if blocked). Password gate (red AND
  ≥10 — compound condition). Tall-enough filter (act per item in a loop).
- **Procedures / `name` builds (#6):** ⭐ Reforestation — define `Tree`, place 12
  (the payoff; matches `tree_showcase.nim`). Lamplit road (proc + loop). Village
  of parameterized houses. Castle (a proto whose script calls another proto —
  verify proto-within-proto).
- **Sequence (#1):** zig-zag stepping stones (order matters); reach a specific 3D
  point by composing up/forward.

---

## Presentation patterns

- **Teaching arc per level:** hook → *show* (live demo) → *tell* (short signs) →
  worked examples → *play* → *exercise* → extend. Mostly signs + demos.
- **Demo station:** the real demo unit is `lock = true` with the messy machinery
  (replay timing, proximity gating, draw logic); the **sign** shows a clean,
  *idealized* "here's the code you'd write," deliberately decoupled from the unit's
  real script. **Controls** (size/count links, or a step-on button) change *both*
  the build and the displayed code snippet (`10.times` → `20.times`). Reusable
  component; great for the Variables level too.
- **Demo replay:** rebuild on a ~10 s timer by default; when the controls sign is
  open, pause the timer and rebuild only on a control click (or rebuild while the
  player is near the buttons).
- **Level-1 onboarding:** a stationary greeter bot (hello + point) + a clear
  visual path. Vary the approach per level — overproduce, pull gems.

## Small Enu changes surfaced (confirm / build as needed)

- **Rider on a `move me` platform** (the linchpin above).
- **Real light sources** — torches/beacons are visual spheres now; true lights
  would need a light node exposed to the VM.
- **Read a voxel's color** at a position from a checker (needed by checkerboard +
  altitude-painter; `floor_at`/`clear_box` give presence, not color).
- **Bot senses the cell ahead** (wall-following bot).
- **Reward animations driven by the checker** (receding water, settling roof) —
  the `door.nim` open-flag pattern already works for doors.
