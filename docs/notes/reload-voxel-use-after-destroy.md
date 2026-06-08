# Reload use-after-destroy: animated builds invalidate their voxel body

**Status:** root-caused to a deterministic repro; fix deferred (needs ed
cross-thread sync semantics + move-mode teardown ordering — overlaps the active
ed/lifecycle work, so not safe to do blind). Found 2026-06-08 on `mcp-server`.

## Symptom

An animated build (`move me` + `loop:`) makes its `…voxels.packed_chunks` Ed
table go invalid (`destroyed = true`) shortly after it loads. Then:

- **Render thread** reads it every frame (`game.nim` stats `walk_tree →
  packed_chunks.len`, and other render paths) → `assert self.valid` fails, is
  caught inside the Godot method, and logs `ERR Ed invalid` ~60×/s (the "40s of
  spam").
- **Worker thread** eventually reloads/resets the build (`worker_thread →
  update_files → … → change_code → reset → voxels.clear → packed_chunks.value`)
  → the same assert, but on the worker thread it is **unhandled** →
  `Error: unhandled exception … self.valid [AssertionDefect]` → **whole process
  aborts**.

`valid = (?self and not self.destroyed)` (`deps/ed/.../validations.nim`). The
log names the id, so it's not nil — the body was **destroyed** (only
`operations.nim:destroy`/`destroy_owned` sets that; the evictor does NOT —
`evict_body` never sets `destroyed`, and `evict_candidate` skips LAZY handles).

## Deterministic repro (~10 s) — no MCP / editor / client needed

Pure filesystem writes + engine-log inspection. It does **not** need an MCP
connection, the in-game editor, or a connected client — just a running Enu with
a level loaded (e.g. the default `skill-test`).

1. Write an **animated** build into the loaded level dir:

   `<level>/data/build_repro1/build_repro1.json`:
   ```json
   {"id":"build_repro1","start_transform":{"basis":[[1,0,0],[0,1,0],[0,0,1]],
    "origin":[150.0,0.0,-150.0]},"start_color":"BROWN","edits":{}}
   ```
   `<level>/scripts/build_repro1.nim`:
   ```nim
   speed = 0
   box(width = 6, height = 20, depth = 1, color = brown)
   box(width = 4, height = 2, depth = 4, at = vec3(1,1,1), color = red)
   move me
   speed = 8
   loop:
     nil -> sleep as down
     down -> up(home + 16) as up
     up -> down(home) as down
   ```

2. `touch` both files; wait ~5 s (initial load — **clean** so far).
3. `touch` the **`.json` again**; wait ~5 s. This second touch is the trigger:
   it mimics what `save_level` does to the data file after a script edit and
   forces the JSON-watch full-reload path
   (`worker.nim`: `state.units -= unit; load_unit_from_json`).
4. Grep the engine log `~/Library/Application Support/enu/logs/enu.log` for
   `Ed invalid` / `build_repro1.voxels.packed_chunks` — it floods (100s of
   lines: ~219 in a clean run). A further reload of that build escalates the
   render-thread spam into the worker-thread `AssertionDefect` that aborts the
   process. (Cleaning up the wedged build requires kill + restart with Enu down,
   then delete the files — deleting it while wedged can itself trip the fatal.)

**Control:** the same recipe with a *static* script (`box(...)`, no `move me`)
goes through the identical remove→add→`init_voxels_if_needed` reload and stays
**valid (0 Ed invalid)**. So the bug is animation-specific, not generic reload.

**Independent of replica/subscribe mode.** Reproduced *identically* with
`partial = false` flipped in both `bin/enu_mcp.nim` and `worker.nim` (line ~549),
rebuilt and restarted: ~219 `Ed invalid` on a fresh server instance — same as
`partial = true`. The partial/subscribe flag is not involved; note a listen-mode
**server** never even executes the worker's `partial` subscribe line (it's the
client-connect path). The cause is the LAZY voxel-table lifecycle +
`init_voxels_if_needed` aliasing, which run regardless of `partial`.

## Mechanism (what the log shows, in order)

1. JSON mtime change → worker JSON-watch reload path
   (`worker.nim` ~246: `state.units -= unit` then `load_unit_from_json`).
2. Render ctx observes a `removed` then `added` for the same id; `add_to_scene`
   → `init_voxels_if_needed` takes the **else/alias branch** (`builds.nim:462`):
   binds the new incarnation's `voxels` to the *still-registered* `ctx[packed_id]`
   body (no "creating new ones" log).
3. `voxel data arriving` → then the old incarnation's deferred destroy
   (`destroy_owned(id)`) frees that aliased body → `destroyed = true`.
4. The live new incarnation now holds a destroyed `packed_chunks`. Render reads
   it (spam); a later worker reset reads it (fatal).

`packed_chunks`/`chunk_deltas` are Ed tables owned by the build id via `id.own`,
but `Unit.voxels` is a **plain (non-Ed) field** (`types.nim:308`) that does not
ride the unit closure — so after any cross-ctx sync it's nil and rebuilt by
`init_voxels_if_needed`, which aliases by id. That id-keyed rebind is the seam
that decouples the body's lifetime from the holder.

## Root cause — confirmed via live repro + stack traces (2026-06-08)

Reproduced on a standalone server (`repro-voxel`, a copy of `skill-test`):
animated reload → **422 `Ed invalid`** on `packed_chunks` (matches the note).
Instrumented `Ed` container `destroy` (stack) + the alias point + the worker
removed-handler. Findings:

1. **The alias is NOT the bug.** At alias time the body is **valid**
   (`packed_destroyed = false`) — the new incarnation correctly aliases a *fresh*
   body. It is killed *afterward*.
2. **Two destroy rounds.** Round 1 (`state.units -= unit` → removed-watch →
   `unit.destroy` → `destroy_owned`, **local**, `publish=true`) destroys the OLD
   body and broadcasts `DESTROY`. The new incarnation then recreates the **same
   id**. Round 2 arrives ~100 ms later via `process_message` (a received
   `DESTROY`) and kills the **reincarnated** body.
3. **Round 2 is a cross-thread echo.** Worker and node *each* destroy on their
   own `state.units` REMOVED and each broadcast. The node's reactive
   `destroy_owned` (fired while applying the worker's removal) re-broadcasts a
   `DESTROY` that lands back at the worker (bidirectional sub) *after* it has
   recreated the id — same id, **no generation to tell incarnations apart**.
   The reactive cascade does not propagate the triggering op's `source`, so
   `publish_destroy`'s source-filter doesn't suppress it.

So the real bug: **a stale cross-thread `DESTROY` for a reused ed id kills its
reincarnation** — the "concurrent same-id creation" case PR #10's LSN design
explicitly left out of scope (`CREATE` is unstamped, so there's nothing to order
a later `DESTROY` against).

### Correction: it is NOT animation-specific

A **static** build (`box(...)`, no `move me`) reload, run **alone in a fresh
standalone server**, also wedges: **1088 `Ed invalid`, all on `packed_chunks`**.
The note's "static stays clean" was likely level/timing-dependent. Treat this as
a *general reload-reincarnation race*, not animation-specific.

### A targeted echo-suppression fix is whack-a-mole (don't ship it)

Tried: thread the source of the op being applied (`process_message`) into
destroys originated reactively, so `publish_destroy` suppresses the echo.
Result: `packed_chunks` → **0**, **but the failure moved to the unit's `units`
collection** (`Ed[seq[Unit]]`) — every same-id'd ed object the reload reincarnates
(packed_chunks, chunk_deltas, `units`, …) has the same race. Fixing one exposes
the next. Reverted; tree clean.

### Recommended real fix (a co-owned ed-sync decision)

Make id-reuse-across-reload safe *generally*, one of:
- **ed: incarnation/generation on the id.** Stamp `CREATE` (and carry it on
  `DESTROY`); a `DESTROY` older than the body's current incarnation is a no-op.
  This closes the PR #10 `CREATE`-unstamped gap and makes reincarnation robust
  for any consumer. The proper fix; a real sync-protocol change — design with
  the LSN/lifecycle owners.
- **enu: reload doesn't reuse ids.** Give each reload incarnation fresh ed ids
  (or do a true in-place update that never destroys+recreates), so no stale
  `DESTROY` can reference the new incarnation.

## Decision + progress (2026-06-08)

**Decided: ed should NOT support destroy+recreate of the same id.** It's
inherently ambiguous under async sync (no generation on the id) and cheap to
avoid. So: detect+report it, and fix enu to not do it.

**Guard (ed, done + verified, asan-clean):** `EdContext.recently_destroyed`
records *synced* (broadcast) destroys; on recreating one within
`recreate_race_window` (2 s), `defaults` **raises `ZenError` in dev / logs ERROR
in release** at the recreate site. Verified on the repro:
> `recreating destroyed id 'build_repro1.voxels.packed_chunks' 414 µs after a
> synced destroy — … Use a fresh id or update in place. [ZenError]`
(Currently uncommitted — landing it alone makes dev reloads raise until the enu
fix lands, since the bug is still present.)

**Fix (enu, in-place reload — RIGHT DIRECTION, BLOCKED):** routed the
existing-unit JSON-watch reload (worker.nim ~245) through a new
`reload_unit_in_place` (`change_code`/`reset`) instead of `remove + readd`. This
**stops the crash** (repro animated + static → **0 `Ed invalid`, 0 guard**,
normal add/delete still work) — but it **does not regenerate the build's
procedural voxels**: `reset()` clears them and the script does not re-run/redraw
on this path (a bigger box via reload produced no bounds change). The old full
reload re-runs the script via `load_unit_from_json` → `SCRIPT_INITIALIZING` +
`load_units` + the normal advance flow, which `change_code` doesn't reproduce.
Reverted (don't ship a build-emptying reload). **Next step:** make the in-place
reload re-run the script the way `load_unit_from_json` does (SCRIPT_INITIALIZING
+ the run flow), not via `change_code`; then reload edits from JSON (needs an
edit-table clear). Needs enu script-execution context.

## SOLVED — three layers, two of them real ed gaps

The reload reuses ids for a new incarnation, and *every* container the build
owns reincarnated onto a destroyed predecessor. Peeling it required fixes at
three levels:

1. **ed — `find_ref` resurrected destroyed instances.** The ref_pool dedup
   (`type_registry.find_ref`) handed `from_flatty` a *destroyed* ref whenever a
   reload reused its id and the old instance still lingered in the pool — so the
   node's "new" build literally *was* the dead one (`unit_destroyed=true` in
   `add_to_scene`). Fix: skip destroyed instances; a merely *removed* ref still
   dedups, so move-identity is preserved. This made the build + its owned tables
   reconnect fresh.

2. **enu — voxel tables hoisted to real `Build` Ed fields.** `packed_chunks` /
   `chunk_deltas` are now `Build` fields with *generated* ids, reconnected by
   reference (no `{id}.voxels.packed_chunks` lookup, no reincarnation). The
   earlier "LAZY field corrupts the ref" failure was a *symptom* of bug #1 (the
   resurrected ref), not a serialization limit — once `find_ref` was fixed, the
   hoist worked. (Confirmed by `tests/partial_tests.nim`: a LAZY EdTable field
   on a registered ref syncs + reloads without corrupting siblings.)

3. **ed `set_owner` + enu synced `Shared`.** `Shared` was never actually synced
   (its `shared_value: EdValue[Shared]` was created but never assigned), so each
   context minted its own local orphan; and even owned correctly, a *standalone*
   EdRef had no synced-ownership path (ed owns containers-by-EdRef and
   EdRefs-by-OWNS_MEMBERS, nothing else). Fixes:
   - **ed `set_owner(ctx, edref, owner_id)`** — index `owned_by` locally,
     re-derived on every context (the OWNS_MEMBERS pattern; no new synced state).
   - **enu**: `init_shared` now *mints + publishes* `Shared` at the root,
     *adopts* `shared_value.value` on replicas, `set_owner`s it to the unit, and
     owns the edit tables under it (generated id). So `destroy_owned(unit.id)`
     tears unit → shared → edit-tables down on every context.

**Verified:** 10 reloads (animated + static) + delete → 0 `Ed invalid`,
0 guard, build regenerates each time, no crash; ed suite 133 green. Landed on
`refactor/object-lifecycle` (ed) / `mcp-server` (enu).

Failed approaches, for the record: ed echo-suppression (shifted the failure to
`units`); enu in-place `change_code` reload (didn't re-run the script); a synced
per-incarnation `voxel_token` (would have worked but the hoist is cleaner and
`find_ref` was the real bug). The recreate-after-destroy **guard** stays as a
dormant backstop — nothing reuses a container id now.

## Why a static build survives but an animated one doesn't (open question — see correction above)

Both take the same reload path and both alias. The static unit's script has
**finished** (`script_ctx.running = false`); the animated unit's script is
**still running** (suspended in `loop:`/move mode). The leading hypothesis: the
old animated incarnation's still-running script / move-mode teardown changes
*when* `destroy_owned` runs relative to the rebuild, so the freed body lands
under the live incarnation. Not yet proven — needs instrumentation of the
exact `removed`/`added`/`destroy` ordering on the worker ctx (the worker-side
reload between the two `loading script` lines logs nothing but
`retry_failed_scripts`).

## Why NOT the obvious fixes

- **Use-site `destroyed`/`valid` guards** (in `voxels.clear`, `Build.reset`,
  `change_code`, the `game.nim` stats walk): they stop the crash + spam but only
  *contain* it — the live build still holds a dead body and renders no voxels
  until its next clean reload. Per project policy we don't want defensive guards
  in dev; in dev we want to crash on state we don't understand. (Implemented,
  reviewed, then reverted — tree is clean.)
- **Blind destroy-before-rebuild ordering**: the right shape per intent
  ("reload = throw the unit's ed data away and rebuild from JSON; clients fully
  reload too") — but doing it safely needs the sync-coalescing + running-script
  teardown answers above, and `worker.nim`'s `for_all_units` removed handler
  deletes the unit's files unless `LOADING_SCRIPT` is held, so the destroy
  timing is load-bearing for data safety. Not safe to guess.

## Recommended fix direction (for when this is picked up with full context)

Make reload a true teardown→rebuild for the unit's voxel body, so no live
incarnation ever aliases a dying one. Either:
1. In the JSON-reload path, fully destroy the old incarnation's owned bodies
   (synchronously, with `LOADING_SCRIPT` held so files aren't removed) **before**
   `load_unit_from_json`, so `init_voxels_if_needed` finds `packed_id notin ctx`
   and creates fresh; or
2. Have `init_voxels_if_needed` refuse to alias a body owned by a different
   (outgoing) incarnation — i.e. only alias for a genuinely live cross-thread
   sync, never for a reload.

Confirm against the repro above (animated must end with 0 `Ed invalid`), and
re-check the static control still works, plus a client/replica run
(`nim mcp_repro` / the `client_smoke` task) since the body is `SYNC_REMOTE`.
