# Session Handoff — Enu 0.3 course + MCP/infra work

Snapshot for resuming cold. For the course *design*, read
`docs/course/{design,loops,exercise-bank}.md`; this doc is "where we are + what's
next." (Updated 2026-07-02: all the infra this doc used to track — the reorg,
the MCP connection model, and the whole platform-riding/adopt feature — has
merged to `main`; the course is unblocked.)

## Branches & PRs

- **`course`** (working branch): the 0.3 course, freshly rebased onto latest
  `main`. Content commits: design+spec, loops pilot (WIP), exercise bank, this
  handoff.
- Everything previously pending is merged: the `share/` reorg + agent files +
  MCP connection model (PR #63), dep unpin + test isolation (PR #62), and
  **platform riding / bot floor-follow / explicit adopt (PR #66)** — see the
  riding section below, it changes the course's feasibility picture
  substantially. Bots also honor `start_color` now (PR #69), so course scenes
  can have colored bots.
- **`course-old` / `course-backup`** (local only): pre-rebase history; delete
  once happy.

## MCP server — connection model (merged)

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

**Platform/riding feasibility — SUPERSEDED by PR #66 (merged 2026-07-02).**
The old caveats no longer apply; the new reality is strictly better:
- **Bots auto-ride** any moving/turning platform they stand on (transform
  matching, no `adopt` call, no lip): they orbit and yaw 1:1 with a turning
  barge, still or walking. Bot-ferries need zero setup.
- **The player rides too** (same mechanism, no lip needed), turns its view with
  the platform's yaw, and inherits platform velocity when jumping off.
- **Bots fall off ledges** (gravity matching the player's) and **climb single
  blocks** (animated hop; 2+-block walls still block) — courses can use ledges,
  gaps, and stairs the bots navigate physically.
- Explicit `me.adopt(unit)` / `unit.release` also exists for deliberate
  reparenting (top-level units only; adopting a nested unit errors — release
  first).
- Details + known interim limits: PR #66's description and the
  `platform-riding-transform-matching` memory note.

## Loops pilot — state: BUILT + VERIFIED (2026-07-02)

`share/worlds/course/loops` is a complete level — see `loops.md` for the
as-built spec. Teaching arc (Pip -> self-rebuilding spiral demo -> lesson sign
-> tap-to-loop sign) + three verified exercises: the striped lighthouse (lamp
+ beam + gate + boat rewards), Salty's stepping-stone crossing (bot puzzle
using the new fall/climb riding mechanics), and Art Beach (pure build).
Code-tool-only via show_tools + a director unit. All seven reward markers
verified headlessly on a pristine copy; signs/facings verified by screenshot.
Remaining: the nim:// tap-to-loop links need one interactive click-test, and
an in-person playthrough for feel.

## Next steps (suggested order)

1. **Playtest Loops Island in person** — the one thing headless can't check:
   feel, pacing, sign sizes/reading order, and the nim:// tap-to-loop links.
2. **Promote Redrock Canyon to a full level** — it has the setting + two
   verified exercises; needs the teaching arc (show/tell/play beats), gating,
   a re-rolled gap for the bridge (anti-copy-paste), and narration.
3. **Fold the ferry into the course** — as the loops level's extension or the
   traversal beat of its own level; the pack-crossing scene is the course's
   marquee moment.
4. **Nested loops + Procedures levels** — pyramid/orchard snippets are
   verified; the Cactus proto proves `name` works in course levels.
5. **Demo-station + replay component** (unchanged from before).

## Gotchas

- **`git add -A` footgun:** `fonts/` is mixed (10 tracked + ~2060 untracked
  downloads); a blanket add sweeps them all in. **Stage specific paths, never
  `-A`.**
- Don't commit to `main` directly; `course` is the working branch.
- Prefer the checker-echo pattern over complex `eval` (JSON-escaping).
