# Enu Programming Course — Design (draft v1)

> Status: draft for iteration. Captures the shape of the 0.3 programming course
> so we can drive down into per-level specs. Nothing here is final.

## Decisions (first pass)

- **Scope:** core through **#6 Procedures**. **No stretch goals** (bots,
  capstone) in 0.3 — go to #6 and make it great.
- **Theme:** **per-level themes, no strong overall theme.** Variety is the point
  — one level "old west," another "space station," etc.; each level should
  **look and feel distinct** from the others.
- **Ambiance:** rich, but **legibility first** — it must be easy to tell where to
  go and what matters vs. background. Exact density we'll dial in by experiment.
- **Assessment:** **check the result, not the code**, by default. Reserve
  code/method checks for special cases where the instruction is about the code
  itself (e.g. "make a height *variable*").

## 1. Goal & audience

Ship Enu 0.3 with a **standalone programming course** — the largest Enu project
to date, spread across many levels in one world. It teaches programming *through
Enu* (3D Logo): you learn by directing a turtle/bot and building voxel
structures.

- **Audience:** general, but **kids ~10–12 are the priority**. Reading level,
  pacing, and reward cadence target them.
- **Standalone:** runs with **no agent attached**. (We may *optionally* run
  sessions with a Claude helper, but the course must stand on its own.)
- **Floor:** loops + variables + general Enu programming. **Stretch is better** —
  ideally through reusable build procedures, with bots/behavior and a capstone as
  reach goals.

## 2. The medium we're teaching with

Enu is 3D Logo. The teachable palette (confirmed from `vmlib/enu` + the example
worlds):

- **Turtle movement** — `forward`, `turn`, `up`/`down`, `move me`, `speed`.
- **Voxel building** — `place`, `box`, `sphere`, `cylinder`, `ball`; `color`;
  `at = vec3(...)`.
- **Build procedures / classes** — `name Foo(params)` defines a reusable build;
  `Foo.new(position = ..., param = ...)` instantiates it. Params can be ranges
  (`trunk_height = 20..32`). This is Enu's most powerful idea (abstraction) and
  the heart of scenes like world1.
- **Bots & behavior** — bots with event/state sections (`-setup:`, `-approach:`,
  …), sensing, movement, `say` (markdown signs).
- **Signs / markdown** — the existing narration mechanism (`say "..."`, rich
  markdown panels). tutorial-1 already teaches this way.
- **Control flow & math** — `times`, `for`, `while`, `if`, `forever`, `import
  math`, `cycle(...)`, `seed`/pseudo-random placement.

**Aesthetic bar = world1** (58 scripts, procedural forests via loops+math,
`SpiralTree.new` classes, animated orbs). It is *not* a tutorial and is barely
interactive — it's the **"large, alive, looks great"** reference. We want that
feel at slightly lower density.

## 3. Core design principles

1. **Concept → challenge in a living scene → solution triggers a visible
   reaction → success verified by an in-world Enu checker script.**
   Deterministic, no runtime agent. "Programmatically checkable" means *an Enu
   script*, not an LLM.
2. **Good-faith correctness, not adversarial-proof.** A determined kid could
   probably fake a pass; that's fine. For someone genuinely following along, the
   checks should do the right thing.
3. **Lesson vs. ambiance split.**
   - *Lesson* = the challenge + its checker. Tightly specified.
   - *Ambiance* = the scene around it. Creative freedom within a theme.
   This split is what makes the multi-agent build phase tractable: agents get a
   precise rubric for the lesson and a mood-board for the scene.
4. **No text input (for now).** The student's input is *code*. The one tempting
   use — entering a height/width to see a variable change the build — is weak
   (those values are really constants). Design the course without text input;
   revisit only if a lesson genuinely needs it (a modal prompt would be the
   minimal version, simpler than a sign-embedded textfield).

## 4. Assessment model (the crux)

A **checker** is an Enu script living in the level that watches for the goal and
reacts (open a door, complete a bridge, light a path, confetti). It replaces the
test harness's `signal_test_complete` with an in-world reward.

**Toolkit available to checker scripts** (already in `vmlib/enu`):

- `all_units()`, `Bot.all`, `Build.all`, `Sign.all` — enumerate/count.
- `bounds(unit): WorldBox` / `bounds_at(...)` — a build's extent → check
  height/width/depth.
- `rendered_voxel_count(build): int` — block count.
- `pending_block_updates(unit)` — detect when a build has settled before
  checking.
- positions (`unit.position`), `units_near`, `distance`, `near`.
- `block_log(unit)` — blocks the player placed by hand.
- `find_by_id`, `frame_count()`.
- Reading another unit's source code — for *method* checks (see below). (Confirm
  exact access during the pilot; this is a likely small gap to fill.)

**Two kinds of check:**

- **Result check** — did the build match spec? (count / bounds / positions). The
  primary, most robust kind.
- **Method check** — did they use the *concept*? (parse the script for `times`/a
  loop, a `var`, a `name` definition). Use sparingly, only where bypassing
  trivializes the lesson — e.g. a loops challenge shouldn't pass by placing ten
  blocks by hand. Good-faith bar; light touch.

**Likely small Enu additions** (confirm during pilot):

- Count blocks within an arbitrary world region/zone (bounds covers a single
  build; a "goal zone fill" check may need region counting).
- Clean script-source access for method checks.
- A reusable **"goal met → reaction"** helper so every level doesn't reinvent
  it.

## 5. Progression

- **Hub world** (a campus / island / town you walk through) connects the concept
  levels and visualizes progress. This is the most "alive/carnival" part.
- **Gated golden path:** each level has a *required core challenge* that unlocks
  the next area (door/bridge/light). Optional extra challenges and a free-build
  playground per level for kids who want more. **Nobody must do every exercise.**
- An Enu "world" is a directory of levels, so each concept ("Loops") is a
  *level*, all inside one course world.

## 6. Curriculum outline (draft — react to this)

Each level: **concept · theme idea · challenge sketch · how success is checked ·
Enu features.**

0. **Hub** — overworld, navigation, intro NPC, progress display.
1. **Sequence & movement** (≈ existing tutorial-1) — move the bot, place blocks
   step by step, open the editor. *Check:* reached the goal / placed the
   expected blocks.
2. **Loops** — repetition. Build a tower N tall to reach a mark; a colonnade of
   pillars; a staircase; a spiral. *Check:* bounds height == N (result) + a loop
   was used (method). *Features:* `times`, `forward`/`up`.
3. **Variables** — name a value; "change one number, change the build." A tower
   whose height/color is a named variable; build it twice with two values.
   *Check:* build matches the variable; structure changes when it does.
4. **Nested loops** — grids/pyramids/fields. A 5×5 orchard; a stepped pyramid.
   *Check:* count / footprint dimensions.
5. **Conditionals** — branch on a value. Color blocks by height; a bot that
   turns when its path is blocked. *Check:* the pattern/behavior matches the
   rule.
6. **Procedures (`name` builds)** — define a reusable build (tree, house, lamp),
   then place many. The "aha" that unlocks world1-style scenes. *Check:* N
   instances of the class exist; the class is defined/used.
**0.3 ends at #6.** Bots/behavior and a capstone game are **out of scope** for
0.3 (good post-0.3 follow-ups). Procedures is where Enu becomes powerful — a
strong note to finish on.

## 7. Anticipated Enu changes

- **Assessment helpers/gaps:** region block-count, script-source access, a
  shared "goal → reaction" helper (§4).
- **Multi-agent isolation:** each *authoring* agent needs its own Enu **and** its
  own MCP **server process**. `launch_enu` (random free port, from the merged MCP
  work) gives each server its own Enu; the open question is whether subagents get
  separate server processes — they likely **share the parent's**, which is the
  collision we hit. Plan: **separate `claude` processes** (each its own
  `.mcp.json` → own server → own Enu), each owning a level dir, integrated via
  git. (Verify Claude Code's subagent-MCP behavior; manual instances are the
  reliable fallback.) **Depends on the `unpin-deps` test-isolation fix landing**
  (so building never corrupts source levels).
- **Text input:** none planned (§3.4).
- Any API gaps surfaced by the pilot.

## 8. Authoring & build-out plan

- **Per-level spec template** (one file per level): concept, theme, the
  challenge(s), the checker (result + any method checks) and the reaction,
  narration beats, ambiance notes/mood-board, required Enu features.
- **Phase order:**
  1. This design doc (align).
  2. Per-level specs.
  3. Enu changes (§7), built + tested.
  4. **Pilot one full level** (me or one agent) — the template + quality bar +
     shakes out tooling.
  5. **Parallel agent build-out** — isolated instances, one level each.
  6. Integration, playtest, polish.
- **What agents get:** the tight lesson spec + checker contract, plus a world1
  mood-board and free rein on set-dressing within the theme.

## 9. Open questions (to resolve next)

Resolved in the first pass: depth (#6, no stretch), theme (per-level, distinct),
ambiance (legibility-first; density TBD), method-checks (result-first). Still
open:

1. **World location** — a new world (e.g. `course`) vs. extending `tutorial`; and
   whether the existing tutorial-1 becomes the Sequence level or we start fresh.
2. **Hub design** — what it looks like, how progress/unlocks are shown.
3. **Reward language** — what "you did it!" consistently looks/feels like.
4. **Ambiance calibration** — how dense per level (dial in via the pilot).
