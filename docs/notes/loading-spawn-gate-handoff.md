# Handoff: loading perf + declarative spawn gate

Branch: **`island-load-perf`** (PR #88 → `course-island`). Working level:
`share/worlds/course/island`.

**Status: IMPLEMENTED (solo/server path).** The design below is built and
verified on the island level — boot and mid-session reload both reveal at the
waterfall with no sink. Deviations from the plan as written:

- Players are carried to `start_transform` at load *start* (not the PLAYERS
  step) so the voxel viewer streams the spawn area at top priority.
- The gate does NOT wait for scripts (ASAP_MODE): gate units' persisted data
  renders in the data phase via prefill; their scripts are usually animation
  and an animated one never finishes. Frame meshes are held under SPAWN_HELD
  and bake right after the reveal.
- "Rendered" is exact, not a settle streak: pending_block_updates == 0 per
  gate build, which is trustworthy because the engine exposes
  has_stream_started (vendor change) and build_node floors the counter at 1
  until streaming has actually begun — plus collision under the player (short
  downward ray in game.physics_process) and a de-embed lift at release.
- load_things pumps ed's flush_buffers per unit — the synchronous load
  otherwise parks every op (including the LOAD_SCREEN clear) in the local
  send buffer until the whole load returns.

The multiplayer extension (remote clients running the same local gate)
remains.

This note carries the full design from a long design session so a fresh agent
can continue. Read it top to bottom before touching code.

## What we're doing / goals

Making the course-island level load feel fast and clean. Concrete goals from the
owner:

1. **~20s (or less) to the player looking at the waterfall, then 30+ fps while
   the rest streams in.**
2. No jarring load artifacts (UI flash before the splash, player sinking through
   un-formed collision, chunks that never render).

## Branch state

**Committed (in PR #88), verified working:**

- `329be43b load: drop main-thread edit decode; prefill terrain from edit_snapshots`
  - `init_voxels_if_needed(rebuild_edits=false)` on the display-side joins — the
    terrain's 1345-chunk `local_edits` decode (~1321ms) doesn't run on main.
    Setup 1368ms→47ms.
  - `prefill_bytes` falls back to `edit_snapshots` when `packed_chunks` hasn't
    synced (race-free; same encoded blob). Prefill 0%→100% of terrain chunks,
    meshed off-main. Node marks `edit_prefilled` so the later packed sync doesn't
    repaint on main.
  - Established: "prefill misses" are **empty air blocks**, not missing data
    (`miss_with_data=0`).
- `228b5ff8 load: opt-in loading splash…` and `6fa6f7ea load: splash from the
  first frame, render off behind it, prefill palette-gated`
  - **These two are being SUPERSEDED by the redesign below.** They added a
    `loading_screen` bool, a `clear_load_screen` VM proc, a `LOAD_SCREEN` flag +
    black full-rect `LoadScreen` node in `game.tscn`, render-off while the splash
    is up, a `palette_published` gate on `enu_chunk_bytes` (KEEP this — it
    prevents serving a prefill blob before the palette map is published, which
    would mesh empty), and a `build_bootstrap` script that positioned the player.
  - The bootstrap approach is being **removed** — see below.

**Uncommitted WIP (compiles):**

- `src/types.nim` — added `SPAWN_HELD` to `LocalStateFlags` (local, never synced).
- `src/nodes/player_node.nim` — `physics_process` freezes the player (zero
  velocity, no gravity/move, zero input_direction) while `SPAWN_HELD in
  state.local_flags`.

## THE DESIGN (declarative spawn gate) — build this

Replaces the whole `loading_screen` bool + `clear_load_screen` proc +
`build_bootstrap` script with a declarative, multiplayer-correct gate.

### Sentinel + level.json

- **`PLAYERS`** sentinel, **always in `load_order`** (if missing, auto-insert at
  **front**). Its *position* is the gate: the units *before* `PLAYERS` are the
  ones that must render before players are handed control. `PLAYERS` first =
  nothing to wait for = immediate physics + `start_transform`, no splash (today's
  behavior, made explicit).
- **`start_transform`** in level.json (basis+origin, same shape units use). The
  player's spawn pose; applies to **all** players including mid-session joins.
  Player already has a `start_transform` field (defaults to `(0,1,0)`).
- **`load_player_with_scripts`** bool in level.json (owner's chosen name).
  Default false. Only needed for the edge case of a *persisted* unit that also
  has a *decoration script* — where you want to reveal after the fast data
  render, not wait for the script. The uniform gate (below) handles the common
  cases without it, so wire the mechanism first and treat the bool as the
  explicit override.

### Two-phase load (data first, then scripts), same load_order

Owner decision: **load all unit DATA first, then run all scripts** (in the same
load_order). Reasons: scripts run against a complete world (no "can't see a
not-yet-loaded proto" retries), and the spawn/reveal becomes fully
script-independent — which deletes the script-starvation problem that made the
old bootstrap fragile (a script that `sleep`s mid-load is starved of VM ticks
until `load_level` returns; that's why the bootstrap's reveal always landed at
load-end).

`load_things` (`src/models/serializers.nim`, ~line 431) becomes:

1. **Data phase**: walk `sorted_scripts`; for each unit load json + `restore_edits`
   + `flush_dirty_chunks` + add to `state.things` (the existing per-unit body,
   lines ~490-517). Script-*less* builds `reset()`+`end_asap()` now (render).
   Scripted builds keep `SCRIPT_INITIALIZING` and defer to phase 2. When the walk
   hits `PLAYERS`: reposition all players to `start_transform` and clear the
   synced `LOAD_SCREEN` (the "you may reveal once rendered" signal). Skip
   `PLAYERS` as a unit.
2. **Script phase**: walk the deferred scripted things in load_order; assign
   `thing.code = Code.init(...)` (runs each script's initial pass → draws →
   `end_asap`).

Note: a *script-drawn* build renders in phase 2, so it appears shortly after the
reveal. For the island that's ideal (terrain/water are persisted; windmill / bots
/ course are the stream-in content).

### The reveal gate (per main thread — server node ctx AND each client)

The server can't know a remote client's render state, so **each main thread gates
itself locally**:

- `LOAD_SCREEN` is **synced, server-authored**: set at load start (when there are
  pre-`PLAYERS` units), cleared by the server at the `PLAYERS` step. Meaning:
  *"splash phase over — reveal once your local pre-`PLAYERS` units render."*
- On each main thread (`game.nim` `process`): while a load is in progress, keep
  `SPAWN_HELD` (local flag) set → splash visible + player frozen + 3D viewport
  render disabled. When `LOAD_SCREEN` clears, **snapshot the builds present at
  that moment** (via a watch on the flag removal, so ed ordering guarantees the
  snapshot is exactly the pre-`PLAYERS` units — they synced ahead of the flag;
  don't snapshot in `process` after a tick or you may include post-`PLAYERS`
  units). Then wait until every snapshot build is **rendered**; then clear
  `SPAWN_HELD` (reveal + unfreeze this machine's player).

### "Rendered" = ASAP ended + voxels settled (reuse `wait_for_script`)

The readiness signal is exactly what the MCP `wait_for_script` tool checks
(`bin/enu.nim` ~line 101): script done + voxel pipeline drained. On load
everything is in ASAP mode, so the `ASAP_MODE` global flag *is* the "drawn vs
not-yet-drawn" distinction I first thought we lacked:

- A **persisted** unit leaves `ASAP_MODE` right after its data restores (phase 1)
  → reveals fast.
- A **script-drawn** unit stays in `ASAP_MODE` until its script runs (phase 2) →
  reveal waits for it. Automatic; no phase choice needed for the common cases.

Per gate build, "rendered" = `ASAP_MODE notin build.global_flags` **and**
`build.pending_block_updates == 0` for a short streak (wait_for_script uses 3
consecutive zeros) — plus a **timeout** (an animated `loop:`/`move me` build never
finishes, and a slow mesh can't hang the load forever). `pending_block_updates`
is main-computed (`build_node.process`) and is an `EdValue` (synced). While
waiting for voxels to settle the script must not be advancing — `ASAP_MODE`
cleared guarantees the initial draw is done.

`load_player_with_scripts=false` → gate on settle only (fast, persisted).
`load_player_with_scripts=true` → gate on ASAP-ended + settle. (Or, simpler:
always gate on ASAP-ended + settle and let the bool trim the persisted+decoration
edge case later.)

### Flags summary

- `LOAD_SCREEN` (synced, GlobalStateFlags): server "splash phase" signal.
- `SPAWN_HELD` (local, LocalStateFlags — DONE): per-main-thread "frozen + splash
  up." `game.process` owns it; `player_node.physics_process` reads it (DONE).
- `SPAWNING` (synced, existing): was the freeze/input flag. Now redundant — input
  gates in `player_node` (~lines 226, 241, 255-257) should read `SPAWN_HELD`
  instead. **Don't delete the `SPAWNING` enum value** (wire-layout / ordinal
  churn — see gotcha below); just stop using it, or repurpose.

## What's left to implement (file-by-file)

1. `src/types.nim`: `SPAWN_HELD` (DONE). Add `start_transform*: Transform` and
   `load_player_with_scripts*: bool` to `GameState` if main needs them synced
   (see sync note). Remove the `loading_screen` field (superseded).
2. `src/models/states.nim`: drop `loading_screen: false`; add defaults for new
   fields.
3. `src/models/serializers.nim`:
   - `LevelInfo`: drop `loading_screen`, add `start_transform` +
     `load_player_with_scripts`; parse both in `from_json_hook` (~line 23).
   - `load_level` (~line 797): ensure `PLAYERS` in load_order (front if missing);
     apply `start_transform` to `state.player`; set `LOAD_SCREEN` iff there are
     pre-`PLAYERS` units; drop the old `loading_screen`→`LOAD_SCREEN` wiring and
     the backstop that cleared it at load-end (the gate reveals now).
   - `load_things` (~line 431): the two-phase split + `PLAYERS` handling above.
   - `save_level` (~line 633/686): write `start_transform` +
     `load_player_with_scripts`, keep `PLAYERS` in load_order, drop
     `loading_screen`.
4. `src/nodes/player_node.nim`: freeze on `SPAWN_HELD` (DONE). Switch the input
   gates from `SPAWNING` to `SPAWN_HELD`.
5. `src/game.nim`: replace the current `booted`/`LOAD_SCREEN` splash block (~line
   216) with the gate: watch `LOAD_SCREEN` removal → snapshot gate builds; drive
   `SPAWN_HELD` + splash visibility + `scaled_viewport` render-off from it;
   timeout backstop; keep "splash visible from frame 1" (LoadScreen node ships
   visible) so there's no UI flash.
6. `src/controllers/script_controllers/host_bridge.nim` + `share/vmlib/enu/players.nim`:
   remove `clear_load_screen` (superseded). Decide whether `spawning`/`spawning=`
   stay (probably drop — `SPAWN_HELD` is local and engine-driven now).
7. `share/worlds/course/island/level.json`: add `start_transform` (waterfall pose
   — the working spawn was pos `(-219.5, ~5.5, -30.5)`, rotation `-7.5`; ground
   top `floor_at(-219,-30)=4`, player rests ~`y=5.3`), replace `build_bootstrap`
   in load_order with `PLAYERS` (currently at index 1, right after
   `build_terrain`), drop `loading_screen`. **Delete `data/build_bootstrap/` and
   `scripts/build_bootstrap.nim`.**

### Multiplayer sync note (do solo first, then extend)

Solo/server-only is the immediate need. For it, `game.nim` can use the
snapshot-on-`LOAD_SCREEN`-clear approach with no new synced fields (main has the
build nodes locally; `ASAP_MODE` and `pending_block_updates` are already synced).
`start_transform` reaches the player via `player.transform` (synced). For remote
clients later: each client runs the same local gate; the server clears
`LOAD_SCREEN` once (synced) and repositions players (synced transforms); no
per-client "did it render" signal is needed because each client gates on its own
render.

## Verification & gotchas (learned the hard way)

- **Rebuild after any `.nim` change**: `nim build` (~15s, outputs `app/enu.dylib`).
- **Rebuild godot** if you're on a fresh checkout or the voxel vendor changed —
  the committed VoxelLibrary bake fix rode a vendor bump (`446bf9cc`), so the
  godot binary must be built from the current vendor: `nim prereqs` (or the
  godot-only prereq task). Without it you're running a stale engine. Build godot
  under `caffeinate` and expect it to take a while.
- **Run under `caffeinate -i`** — this machine sleeping froze/dropped runs.
- **`--minimized` throttles physics AND the VM tick** — script `sleep`s stretch
  way out and frame counts stay low, which makes timing/`SLOW_FRAME` logs
  misleading. Use a visible window for realistic timing; use minimized only for
  non-timing log capture.
- **MCP has been flaky** — reconnect can throw `netty reactor.id == conn.reactorId`
  (retry once, it usually connects) and the server can drop mid-session. Fallback:
  `bin/enu` CLI with `ENU_CONNECT_ADDRESS=127.0.0.1:49624`. Launch godot directly
  with `--listen 127.0.0.1:49624` and `connect()` rather than `launch_and_connect`
  (which kills its instance on exit). Note MCP screenshots use a **separate 3D
  viewport** and **cannot** show the 2D splash overlay — verify the splash via
  logs/flags, not MCP screenshots.
- **Perf logging**: `ENU_PERF_LOG=1` enables `SLOW_FRAME`/`PERF`/`TERRAIN` lines.
  `ENU_SLOW_FRAME_MS=NN` sets the hitch threshold. `ENU_NO_PREFILL=1` A/B toggle.
- **`bin/enu` goes stale** when model/flag wire layouts change (adding
  `SPAWN_HELD` to an enum, new synced fields) → "key not found: root_things" /
  index errors from MCP tools. Rebuild `bin/enu` after such changes.
- **Don't reorder/remove existing enum values** (GlobalStateFlags,
  LocalStateFlags) — ordinals are on the wire; append only.
- **`git checkout level.json`** reverts to the committed version, which currently
  still has the OLD load_order (with `build_bootstrap`, no `PLAYERS`). Don't do
  that after editing it, or you lose the gate wiring.
- Fast tests: `nim test`. Full (before merging): `nim test_all`.

## Run commands

```
cd /Users/scott/src/enu
nim build            # rebuild the dylib after .nim edits
nim prereqs          # rebuild godot (fresh checkout / vendor change)
cd app && caffeinate -i ../vendor/godot/bin/godot.osx.tools.arm64 \
  scenes/game.tscn --world /Users/scott/src/enu/share/worlds/course --level island \
  --listen 127.0.0.1:49624
```
