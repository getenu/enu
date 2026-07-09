# Durable Persistence — enu on the ed store

> Status: **design / plan.** How enu adopts ed's durable store (log + snapshots +
> restore — ed PR #30) for world, player, and script persistence. Companion to
> ed's `docs/persistence.md` (the store mechanics) and
> `docs/decentralization-and-scaling.md` (the trust/topology/serializer
> direction). This is the plan we execute against; nothing here is built yet.
> Grounded in an audit of enu's object graph (`states.nim`, `units.nim`,
> `builds.nim`, `voxels.nim`, `worker.nim`, `serializers.nim`).

## Goal

Close and reopen a world and get it back — faithfully, and without re-running
every build script at startup. Grow that into persistent player state, resumable
scripts, and eventually a hand-editable, git-friendly on-disk representation. The
ed durable store is the substrate; this doc is how enu maps onto it.

## The three axes (don't conflate them)

Three orthogonal classifications, and the mistake is using one as a proxy for
another:

- **Sync** — `SYNC_LOCAL` (cross-thread) vs `SYNC_REMOTE` (networked). About *where
  an object propagates*.
- **Persistence** — does it survive close/reopen? About *world content vs session
  state*.
- **Presence** — is it "here because someone is connected" (a player avatar) vs
  "part of the creation"? About *lifecycle*.

Sync is **not** a usable persistence signal: many `SYNC_LOCAL` fields (collisions,
sight/eval queries, console log, net/mem telemetry) must sync cross-thread yet
must never be saved. So persistence needs its own opt-in flag (`PERSIST`, below),
and presence is handled by the existing `EPHEMERAL` unit flag.

## What persists vs what doesn't

| Persist (world content) | Don't persist (session / presence / derived) |
|---|---|
| `root_units` → the **non-`EPHEMERAL`** unit graph: `transform`, `code`, `color/scale/glow/speed/anchor`, `global_flags`, child `units`, `shared` | **`EPHEMERAL` units** — player avatars, agent bots/builds (presence) |
| `Build.packed_chunks` + `chunk_deltas`; `Shared.edit_snapshots` + `edit_deltas` (packed voxel blobs) | GameState UI/session: `local_flags`, `wants`, `open_unit`, `open_sign`, `tool`, `tools`, `console.log`, `queued_action`, `status_message`, `server_ctx_name`, `state_global_flags` |
| `level_name` | Telemetry: `voxel_tasks`, `net_*`, `ed_mem`, `test_exit_code` |
| **NEW:** durable `PlayerRecord`s (below) | Per-unit derived (`SYNC_LOCAL`): `collisions`, `sight_query`, `eval`, `velocity` (transient), `current_line`, `errors`, `query`, render counters |
| — | `config` → stays user-global in `config.json` (unchanged) |

`PERSIST` mostly re-expresses a distinction enu already computes: `save_level`
already skips `EPHEMERAL` units, and units already carry `save=true/false` at
creation. `PERSIST` is the container-level encoding of that same decision.

## Object identity & the `init`/`create` model

The ed store preserves whatever id an object has — a generated id is logged on
create and restored intact, with reference integrity across the graph. So durable
objects **do not** need to become static-id; few call sites change:

- **Static-id singletons** (`root_units`, `level_name`): unchanged. ed's `init`
  becomes **get-or-create by id** (reuse if present — e.g. restored — else create),
  so these gain restore-awareness with no call-site edit. `create` is the explicit
  "always new, raise on id collision" escape hatch.
- **Generated-id durable objects** (builds, bots, voxel tables): stay generated.
  The store *restores* them instead of `load_level` *recreating* them.
- **New:** the `PlayerRecord` needs a stable cross-session id (below).

The old silent-clobber footgun (re-`init` of a live id overwrites it with an empty
body) disappears: `init` reuses, `create` raises.

## Player: identity vs presence

The player-as-unit (`root_units`, id `player-{ctx.id}`, `EPHEMERAL`) **is
presence** — reaped ~10s after disconnect (netty `connTimeout` → ed `unsubscribe`
→ worker reaps `EPHEMERAL` units), which cascades `destroy` and frees its state.
So anything durable **cannot** live on the avatar. The split:

- **Stable player id in `config.json`** — generated once, survives sessions
  (`player-{ctx.id}` is only stable per connection).
- **A durable `PlayerRecord`** (position now; inventory/progress later) in a
  `PERSIST`-flagged collection *outside* `root_units` — not `EPHEMERAL`, so
  eviction never touches it.
- **The avatar mirrors the record** for live play: on connect, get-or-create the
  record by the config id and spawn the avatar from it; on disconnect the avatar is
  reaped, the record persists.

Migrate now (even with just position) — the indirection is harder to retrofit than
to reserve.

## The voxel world: what today loses, what the store fixes

Three representations exist, and **what syncs is a superset of what persists**:

- `local_voxels`/`local_edits` (`VoxelStore`) — decoded working set, unsynced,
  rebuilt per side.
- `Shared.edit_snapshots`/`edit_deltas` — packed **hand-placed** edits. Synced.
- `Build.packed_chunks`/`chunk_deltas` — packed **full world** (manual +
  script-computed). Synced, `LAZY`.

Today's JSON save (`$Unit` → `edits_to_string(shared.edit_snapshots)`) persists
only the hand edits, **decoded to world-space and re-packed on load**. So it drops:

1. **The entire script-computed world** — `packed_chunks` is never saved; computed
   voxels come back only by **re-running scripts at launch**.
2. **The packed format + delta history** — decode→JSON→repack loses the exact bytes
   and the append-only `*_deltas` edit history (no voxel time-travel).
3. **Script-owned properties** (e.g. `scale`) — deliberately recomputed.

This isn't corruption — it's a deliberate **"store the inputs (manual edits +
script source), recompute the outputs (computed voxels)"** model, with scripts as
durable input.

The ed store persists `packed_chunks`/`chunk_deltas` faithfully (packed bytes, and
the delta history *is* the log), so the full computed world materializes from the
store **without re-running scripts**. That flips the invariant: once outputs are
persisted, you can't both materialize *and* blindly re-run build scripts (redundant
compute + non-idempotent side effects). Which forces the script model below.

## Scripts on resume

### VM-state resume: investigated, rejected

enu scripts run on the **Nim compiler's VM** (a nimscript-style register-bytecode
interpreter from the getenu Nim fork) — one shared VM per worker thread,
cooperatively stepped per tick, suspending by raising `VMPause` at host-action
points (`move`/`sleep`/…). A script's continuation is `(PCtx, pc, tos)` where the
`tos` registers hold **raw pointers into the compiler's live AST/symbol graph** and
blocking actions park state in an **un-serializable native closure** (`ctx.callback`).

Serializing that means reconstructing a coherent slice of the compiler heap with
stable identities in a fresh process, plus the native callback — deep, permanent
surgery in the compiler fork. The codebase already votes on this: the `flatty`
hooks for `ScriptCtx` are no-op `discard` stubs. **Do not build true VM-state
resume.** (Deterministic replay is also rejected: enu breaks determinism with
startup `randomize`, per-tick `shuffle`, and wall-clock timing, and long scripts
replay slowly anyway.)

### The model we build instead: restart + checkpoint

- **Restart background scripts from the top** (baseline; the machinery already
  exists via level-load / file-watch reload). Build-only scripts don't re-run —
  their output is materialized from the store.
- **Checkpoint API** — scripts opt into a durable, flatty-serializable `state[...]`
  KV persisted per unit. On restart they run from the top but read their state back
  and branch to a resume point. This **is** the 0.3 "script persistence" feature;
  the store is its substrate. Author-controlled resume points are the right model
  given cooperative yielding.

### Wrinkle 1 — dependency-ordered VM rebuild

Some non-running scripts must still re-run at startup to populate the shared VM —
prototypes and any script providing definitions others reference. This rebuilds VM
*state*, distinct from world content. Re-run the dependency closure in
topo-sorted order (the dependency graph already exists), deps first.

### Wrinkle 2 — stash computed voxels instead of clearing

Today every non-checkpoint script relies on "clear my computed blocks at start,
then rebuild." Replace **clear** with **stash aside**:

- A **checkpoint-aware** script reclaims its stash and skips the rebuild (fast).
- A **legacy** script never reclaims, rebuilds exactly as today, and the stash is
  tossed on its first yield or when it ends.

This makes materialize-from-store safe **without converting any scripts** — old
scripts rebuild over their own stash and never notice; new ones get the fast path.
The stash covers only *computed* voxels (script output); hand-placed manual edits
persist independently and are never stashed. "Restore my computed blocks" is part
of the checkpoint API.

## JSON as an editable view (future)

The log is the source of truth; JSON is a **materialized, editable projection** —
editing the JSON issues operations against the log, identical to editing the world.
The filesystem is a *state-based* replica (it tells you what it *is*, not what it
*did*), so reconciliation is a **three-way merge**: record the base LSN a file was
materialized from, reconstruct the base via the store's `replay_to`, and diff
current-JSON and current-log against it. Direction is then *detected*, not guessed —
only-JSON-changed flows in, only-log-changed regenerates, both-changed merges at
field granularity with escalation for genuine same-field conflicts. A missing base
falls back to log-wins-with-a-warning. Git ultimately subsumes this (its merge-base
+ file history *is* the mechanism); the base-LSN/hash is the pre-git bridge. The
editable projection needs the field-named codec (nim-serialization); voxels stay
opaque blobs edited in-world.

## Build outline

**Prerequisites — ed primitives (small, unblock everything):**
- `PERSIST` flag; store persists iff set (replaces persist-iff-synced), orthogonal
  to sync flags.
- `init` → get-or-create by id; `create` → always-new, raise on collision.
- `track(replay = true)` + a `filled()` sugar predicate.
- *(Store + schema gate: done — ed PR #30.)*

**Phase 1 — enu: store attach + isolated wins.**
- Attach the store on the worker (authority), per level dir.
- Player identity/presence split: stable id in `config.json`, durable `PlayerRecord`
  outside `root_units`, avatar rehydrates from it.
- Checkpoint API part 1 — durable KV (no world entanglement).
- Scripts still re-run/rebuild as today.
- *Delivers:* player state survives restart; scripts can save progress (the 0.3
  features), with none of the world/script-rebuild entanglement.

**Phase 2 — enu: durable world + script re-run model (the big one).**
- `PERSIST`-flag the world containers (unit graph, voxel tables, `level_name`).
- World materializes from the store (faithful voxels + history; no lossy
  re-derivation).
- VM-state rebuild in dependency order (wrinkle 1).
- Computed-voxel stash (wrinkle 2) + checkpoint API part 2 ("restore my computed
  blocks" + resume-point branching).
- Background scripts restart from top; checkpoint-aware ones skip to resume.
- *Delivers:* fast startup (no full rebuild), faithful voxel persistence, script
  resume.

**Phase 3 — later: JSON as an editable view + git.**
- Field-named codec (nim-serialization) for the durable path; voxels stay blobs.
- JSON editable projection + base-LSN three-way-merge bidirectional sync; log is
  authority.
- Git integration (store dir as a repo; merge-base subsumes the base-LSN;
  git-hosting / first-joiner authority).

The natural first PR is the ed primitives — small, and `PERSIST` gates the rest.
Phase 1 is the satisfying first enu milestone (visible value, low entanglement);
the world/script-rebuild change all lands in Phase 2.

## Open questions

- **Store granularity/location** — per-level (`level_dir/store`) vs per-world;
  `level_dir` matches today's unit-of-save.
- **`config` scope** — stays user-global in `config.json`; revisit if per-world
  overrides are ever wanted.
- **Script-owned properties vs the store** (e.g. `scale`) — when the world
  materializes, who is authoritative if a script also sets it? Likely: build-only
  scripts don't re-run, so the store value stands; a checkpoint-aware script that
  re-runs reconciles via its declared state.
- **Coexistence vs replacement of `save_level`** — recommended path is migrate world
  content onto the store and demote JSON to export/interchange, but Phase 2 is the
  point that decision gets executed (backups, templates, migration flags all key off
  the current JSON layout).
