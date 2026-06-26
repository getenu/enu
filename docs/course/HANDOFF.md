# Session Handoff — Enu 0.3 course + MCP/infra work

Snapshot for resuming cold. For the course *design*, read
`docs/course/{design,loops,exercise-bank}.md`; this doc is "where we are + what's
next."

## Branches & PRs

- **PR #63 `reorg-agent-mcp` → `main`** (awaiting review + FF-merge). Three infra
  changes split out of the course work:
  1. `vmlib/` → `share/{vmlib, worlds, agent}`; test worlds → `tests/worlds/`.
  2. Agent files: dropped the Claude plugin; Enu generates a project `.claude/`
     (skills/commands/examples + `settings.local.json` that pre-approves the MCP)
     owned via a single `.enu_managed` marker (wipe-and-rewrite if present,
     hands-off if the user deletes it).
  3. MCP server connection fix (see below).
  `nim build` + `nim test` green on the branch. **When it merges, `course` is
  already on top of it** — rebasing `course` onto `main` is a no-op.
- **PR #62 `unpin-deps` → `main`** (awaiting review). `ed 0.30.1`/`nimcp 0.10.0`
  + `--temp-workdir` test isolation + bulk-spawn fix. Independent; `course`
  doesn't need it yet, but the isolation fix matters before running the full test
  suite / letting multiple agents build levels (so runs can't corrupt sources).
- **`course`** (working branch): the 0.3 course, sitting on top of
  `reorg-agent-mcp`. Content commits: design+spec, loops pilot (WIP), exercise
  bank, this handoff.
- **`course-backup`** (local only): pre-rebase `course` history; delete once happy.

## MCP server — new connection model (PR #63)

The server now **serves immediately** (it used to block on a startup connect to
an absent Enu → the client's `initialize` timed out → `-32000`). Tools:

- `launch_and_connect(level_dir)` — spawn a private Enu (random port, minimized)
  + connect; killed on disconnect/exit. (Replaces `launch_enu`.)
- `connect(address = "")` — attach to a running Enu (default `127.0.0.1`, ed's
  default port 9632). **The Enu must have been started with `--listen`.**
- `disconnect()` — detach; kills a launched instance. (Replaces `kill_enu`.)
- Tools return a clear error when not connected; a connect to a dead address
  fails in ~10s (netty's `connTimeout`). The generated `CLAUDE.md` tells agents
  to attach first.

### Driving Enu headless (how this was tested)

- One-shot: `printf '<jsonrpc lines>' | ./bin/enu mcp` with `launch_and_connect`
  → `wait_for_script(unit, timeout)` (returns the unit's bounds, or acts as a
  delay for `forever:` units that never "finish") → `get_console` / `screenshot*`
  → `disconnect`.
- Visible **and** listening (human sees it, agent connects): run godot directly —
  `./vendor/godot/bin/godot.osx.tools.arm64 --path app scenes/game.tscn --level-dir <dir> --listen 127.0.0.1:9876`
  then a separate `ENU_CONNECT_ADDRESS=127.0.0.1:9876 ./bin/enu mcp` (it won't
  kill the instance — it didn't launch it).
- **eval gotcha:** the eval `code` is a JSON string; inner `"` (e.g.
  `find_by_id("x")`) must be JSON-escaped or the request breaks. Easiest: have a
  checker unit `echo` what you need and read `get_console`, instead of complex
  eval.

## Course design — durable docs + principles

- `docs/course/design.md` — scope (through #6 Procedures), per-level themes,
  in-world checker assessment, lesson-vs-ambiance split.
- `docs/course/loops.md` — Loops level spec + the per-level template.
- `docs/course/exercise-bank.md` — 3-agent brainstorm synthesis: recommended
  exercises, full idea bank by concept, the two checker patterns, the
  "strictly-loop-required" trick, presentation patterns, feasibility verdicts.

**Principles (don't lose these):**
- **Turtle-first**: teach `forward/back/up/down/left/right`, `turn`,
  `box/sphere/cylinder` — NOT `place(x,y,z)` coordinates.
- **World-grounded goals**: the loop produces something you physically use.
- **Strictly loop-required**: spaced items (stones/torches/pillars) or
  per-iteration variation defeat one-shot primitives (`up N`/`wall`/`floor`).
- **Checker pattern** (`share/worlds/course/loops/scripts/build_lamp.nim`): a
  `forever:` unit polls `Build.all` → reads `bounds` → latches → reward.
- **Build-measure checkers** (read the student's build) are headless-verifiable;
  **player/bot-position checkers** need a human to confirm the traversal.

**Verified platform/riding feasibility:**
- Elevators work as-is.
- Ferry / horizontal platform: the **player** rides with a **1-block lip**
  (confirmed); needs raised terrain on flat ground.
- **Bots do NOT auto-ride** a moving platform (verified — a bot stayed at its
  spawn z while the barge moved away). → bot-ferry needs the `adopt` task below,
  or position-sync.

## Loops pilot — state

`share/worlds/course/loops/` currently has the lesson-opening prototypes —
`bot_guide` (greeter "Pip"), `build_path` (black road + curbs), `build_demo`
(self-building spiral), `build_lesson1` + `build_trydemo` (signs) — plus the
**old place-based `build_lighthouse`/`build_lamp`** exercise (to be replaced by
turtle exercises).

**Verified staircase exercise** (built + tested in `/tmp`, not yet in the level —
the cleanest first exercise: strictly loop-required, build-measure checker, fully
verifiable). Reproduce:
- student solution — `color = brown` then `8.times:` → `box(2,1,2,brown)`,
  `forward 1`, `up 1` (a 9-tall staircase).
- checker (`build_gate`, at the ledge) — `box(5,4,1,black)` sealed, then
  `forever:` poll `Build.all` for `build_stairs` with
  `bounds.max.y - bounds.min.y >= 7` → `box(5,4,1,white)` (opens) + `echo`.
  Verified: the gate opened.

## OPEN TASK — `adopt` (reparent a unit so it rides a platform)

Designed + investigated, **not implemented**. Lets a platform carry a bot
(bot-ferry) or the player (rider-sticks). Decided to do this as a focused, tested
pass rather than rush it at the end of a long session.

- **Machinery already exists:** the node controller reparents Godot nodes when a
  unit moves between `.units` collections (`src/controllers/node_controllers.nim`
  `watch_units` ~:146) and when `GLOBAL` toggles (`set_global` ~:105); Godot
  composes transforms through the nesting (instanced children move with the
  parent — user-confirmed). `.units` + `global_flags` are ed-synced, so **no new
  bridge plumbing** is needed.
- **adopt(parent, child):** detach `child` from its owner (root `state.units` or
  current `parent.units`), drop `GLOBAL` (so it nests under the parent, not at
  root), add to `parent.units`, shift transform **world → parent-local** so it
  doesn't jump.
- **release(child):** reverse → back to root `state.units`, transform → world.
  (Required: must be able to re-root an adopted unit.)
- **Three things to nail:** (1) expose `me.adopt(unit)` / `unit.release` to the VM
  (`.units`/`parent` aren't script-reachable today — add bridged ops in
  `share/vmlib/enu/base_bridge.nim`); (2) the **transform conversion** — mirror
  `set_global`'s origin shift (`node_controllers.nim:111-117`, which uses
  `start_transform.origin` as the parent offset) so the rider stays put on
  (de)parenting — the fiddly part; (3) **GLOBAL fit** — adopted units must be
  non-GLOBAL (node nests under the parent).
- **Key files:** `src/types.nim` (`Unit.units` :286, `GLOBAL` :131),
  `src/models/units.nim` (`fix_parents` :6), `src/controllers/node_controllers.nim`
  (`set_global` :105, `watch_units` :146), `share/vmlib/enu/base_bridge.nim`.
- **Test:** nest a bot under a moving platform via `adopt` → it rides; `release`
  → re-roots; neither jumps.

## Next steps (suggested order)

1. **Build loops exercises** (course progress, no engine change): formalize the
   **staircase** into the loops level (real ledge/gate scene + the student
   *stub* + a teaching sign + `lock = true` on non-student units); then
   **stepping-stones-with-gaps** (build-measure, verifiable); then the
   **player-ferry** (raised terrain + lipped barge + player-crossing checker).
2. **`adopt` feature** — implement + test, if we want bot-ferries / player-carry.
3. **Demo-station + replay** — the reusable demo component: a `lock = true` real
   unit with the messy logic + a sign showing *idealized* code + controls that
   update both the build and the shown snippet; replay on a ~10s timer, paused
   while the controls sign is open.

## Gotchas

- **`git add -A` footgun:** `fonts/` is mixed (10 tracked + ~2060 untracked
  downloads); a blanket add sweeps them all in. **Stage specific paths, never
  `-A`.**
- Don't commit to `main` directly; `course` is the working branch.
- Prefer the checker-echo pattern over complex `eval` (JSON-escaping).
