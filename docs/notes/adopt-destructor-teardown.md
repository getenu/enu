# Adopt / reparent + destructor-driven node teardown

Design spec + status for letting a unit ride a moving platform (bot-ferry,
rider-carry). Written after a deep investigation pass; supersedes the (wrong)
"adopt = move between `.units` collections, no new plumbing" note in the old
session handoff.

## TL;DR

- **Done & committed** (`adopt-lifecycle`, on top of `course`): `node.model`
  is now a `{.cursor.}` on the four Unit-bearing nodes — breaks the
  `unit.node` ⇄ `node.model` reference cycle so a unit that leaves all owning
  collections can be reclaimed by ORC. Build + fast tests green; world tests
  4/5 (one pre-existing voxel-teardown flake, see below).
- **Implemented** (`adopt-lifecycle`): `me.adopt(unit)` / `unit.release` via the
  `TRANSFERRING` flag (see "Decided approach"). Builds; fast tests green; all new
  behavior is gated on `TRANSFERRING`, so non-adopt paths are unchanged.
  **In-world ride not yet validated** — blocked on the `test_world` isolation
  fix (see "Test prerequisite").
  - Guard sites: `node_controllers.nim` — `set_global` skips its origin shift
    while transferring; `add_or_defer` early-returns for a unit that already has
    a node (relink); the three removed-watchers skip `remove_from_scene`; the
    `state.units` added-path clears a stale `parent` (for `release`).
    `worker.nim` `for_all_units` skips re-join (added) and skips
    destroy/unmap/file-removal (removed). `host_bridge.nim` `adopt`/`release`;
    declared in `share/vmlib/enu/base_bridge.nim`.

## Decided approach (interim — agreed)

Ship `adopt` now behind a transient flag; do the clean destructor-driven
teardown as a follow-up. Tracking issues:
- **getenu/enu#65** — destructor-driven model + node cleanup (the real fix; will
  let us delete the flag).
- **getenu/ed#26** — `set_owner` transfer / single-owner invariant (for the
  eventual membership/ownership split).

Interim plan:
1. **Ownership moves with membership, for now.** `adopt` removes the unit from
   its current units collection and adds it to the new parent's `.units`
   (`OWNS_MEMBERS`), so the platform owns the rider until #65/#26 land. The
   membership-vs-ownership split (riders not owned by the platform; re-home a
   non-owned member on parent destroy) is deferred.
2. **`TRANSFERRING` flag** routes the watchers: `adopt` sets it, does the
   collection remove/add, clears it. The node_controller removed-watcher and the
   worker's reap path **skip destroying a `TRANSFERRING` unit** — so a move
   detaches/re-attaches the node instead of tearing it down. Not blanket `pause`;
   an explicit, intent-named signal that the destructor work later removes.
   - **Flag scope:** the membership move syncs remotely (`.units` is
     `SYNC_REMOTE`), and every context that applies it runs the same
     removed→destroy path — so the flag must reach them all. Make it a
     **`GlobalModelFlags`** (`SYNC_LOCAL + SYNC_REMOTE`), not a `local_flags`
     entry (`SYNC_LOCAL` only reaches worker↔main — fine single-process, a
     latent MP bug). `TRANSFERRING` is a transient *fact about the unit*, not
     per-view state, so global is also the right semantic home.

## Why the original plan was wrong

The old handoff said: "adopt = move the unit between `.units` collections; the
node controller reparents the node; no new bridge plumbing needed."

1. **Collection-removal == destroy, today.** `units` is `OWNS_MEMBERS`
   (`models/units.nim:46`). The node controller's `watch_units`/`state.units`
   `removed` branches call `remove_from_scene` → `unit.destroy`
   (`controllers/node_controllers.nim:153,193,43`). So moving a unit by
   collection membership *destroys* it.
2. **`set_global` doesn't move to an arbitrary parent.** It only swaps the
   node between `state.nodes.data` (root) and `unit.parent.node`
   (`node_controllers.nim:105-117`), reading whatever `unit.parent` already is.
   `GLOBAL` is just "node at root vs under my existing parent" — not a mover.
   Its only relevance to adopt: an adopted unit must end up **non-GLOBAL** so
   its node nests under the platform and Godot composes the transform.
3. **`set_global`'s transform shift is the wrong offset** for adoption — it
   uses `unit.start_transform.origin` (the child's spawn offset), correct only
   for a unit instanced *at* its parent. An adoptee needs the **parent's**
   current world origin.

## The corrected model (verified against ed + enu)

- **ed already does "remove = unlink, not free."** `type_registry.nim:270`:
  *"REMOVE only unlinks — it never frees... This is what gives move-identity
  for free: a removed-then-readded replica re-links the same instance."* A body
  is freed by ORC when its last real reference drops; `RefHandle.=destroy`
  (`ed/types.nim:724`) then prunes `ref_pool`. **enu's eager destroy-on-remove
  is a node-controller policy layered on top of ed, and it's out of step with
  ed's own model.**
- **`owned_by`** (`ed/types.nim:408`, public) is the authoritative, *synced*
  move-vs-delete signal: on ADD to an `OWNS_MEMBERS` collection,
  `owned_by[owner].incl(id)`; on REMOVE, `excl` (`type_registry.nim:285-300`).
  Re-derived identically on every context from the synced ADD/REMOVE, so the
  **main thread** sees it without extra plumbing.
- **`EdRef.destroy()`** (`ed/zens/operations.nim:477`) is *not* redundant with
  ORC: it `lifetime.finish()`s, then `destroy_owned(self.id)` which broadcasts
  DESTROY so replicas tear down their mirrors **and** tears down the standalone
  `Shared` voxel tables attributed via `id.own:`. So on a **true delete**
  `unit.destroy` must run; on a **move** it must not.
- **Cross-thread (the key constraint).** Two ed contexts: `main`
  (`game.nim:206`) and `worker` (`worker.nim:412`); worker subscribes to main
  (`worker.nim:426`). The "same" unit is **two objects**, one per thread,
  synced by serialized channel messages. **Only the main-thread unit carries
  `.node`** (set in `add_to_scene`, main thread). `state`, `current_build`,
  `previous_build` are `{.threadvar.}` — so a main-thread `=destroy` touches
  only main-thread state, and `queue_free` is legal there.
  - Consequence: **`host_bridge` runs on the worker thread, where `unit.node`
    is nil.** `adopt` can only do *ed* ops on the worker; the **main thread**
    must do the node reparent in reaction to the synced ed changes — exactly
    how `set_global` already works (worker toggles `GLOBAL` → syncs → main's
    `global_flags.watch` → `set_global` reparents). The move-detection signal
    must therefore be **synced state (`owned_by`)**, never a worker-local flag.

## Design for `adopt` / `release`

### Worker side (`controllers/script_controllers/host_bridge.nim`, new procs)

`adopt(platform, unit)` — pure ed ops, add-first so the unit is re-owned
before the old removal fires:

```
let old_owner = if ?unit.parent: unit.parent.units else: state.units
platform.units.add unit          # owned_by[platform.id].incl(unit.id)
old_owner -= unit                # owned_by[old].excl; unit stays alive (re-owned)
unit.global_flags -= GLOBAL      # drives the node reparent on the main thread
unit.transform_value.origin =    # world -> platform-local (origin-only)
  unit.transform.origin - platform.transform.origin
```

`release(unit)` — mirror: `state.units.add unit; platform.units -= unit;
unit.global_flags += GLOBAL; origin += platform.transform.origin`. (`platform`
= `unit.parent` at call time.)

Expose via `share/vmlib/enu/base_bridge.nim` (`bridged_to_host`): `proc
adopt*(self: Unit, unit: Unit)` and `proc release*(self: Unit)`. Note today's
VM API has no way to reach another unit's `.units`/`parent` — adopt/release are
the bridged ops that do it.

### Main side (`controllers/node_controllers.nim`) — two additive guards

The node reparent itself is already handled by `set_global` firing from the
synced `GLOBAL`-removed change (it reparents the node to `unit.parent.node`,
which `fix_parents` has set to the platform). We only need to stop the *other*
two watchers from rebuilding/destroying the node for a relink:

1. **`add_or_defer` / added watch**: `if ?unit.node: return` — the unit already
   has a node (it's a relink, not a fresh spawn); the reparent comes via
   `set_global`. (Fresh units always have `node == nil` here, so normal spawns
   are unaffected.)
2. **`removed` branches** (`watch_units` + `state.units`): skip
   `remove_from_scene` when the unit is **owned elsewhere** —
   `unit.id in ctx.owned_by.getOrDefault(<other owner>)`. Normal deletes
   (`clear_all`, `delete`, `claim_name`, reload) are never owned elsewhere, so
   they take the exact current path. **This is the safety property: the new
   branch only triggers mid-move.**

A helper like `proc relinked(ctx: EdContext, unit: Unit, from_owner_id: string):
bool` that scans `owned_by` for `unit.id` under any owner ≠ `from_owner_id`.

### Transform / `set_global` cleanup

`set_global`'s origin shift uses `start_transform.origin` (wrong for an
arbitrary adoptee). Two options: (a) let `set_global` run its (wrong) shift and
let the synced `transform_value` change from the worker overwrite it — final
state correct, possible 1-frame flicker; (b) cleaner: teach `set_global` to use
`unit.parent.transform.origin` as the offset when the parent isn't the root.
Prefer (b) once it's the adopt path; verify it doesn't regress the existing
instanced-child GLOBAL toggle.

### Rotation caveat

`global_from`/`local_to` (`core.nim:233/240`) are **origin-only**. A
*translating* platform (ferry, elevator) is fine. A *rotating* platform won't
rotate the rider — that needs full-basis composition in the conversion.

## The destructor-driven endgame (the "right" version)

The guards above are surgical but still leave enu's "remove = destroy" policy in
place for the non-move path. The clean end-state, which the cursor commit is the
first step toward:

- Add a **main-thread `Unit`/`Model` `=destroy`** that frees `self.node`
  (`node.model = nil; node.queue_free()`), safe because the node-bearing unit
  is main-thread-local (see cross-thread note). Mirror ed's deferred pattern
  only if profiling shows reclaim happening off the main thread (it shouldn't).
- Make the `removed` watcher **never** free the node — removal just drops
  ownership; the node dies with the unit (ORC) via `=destroy`.
- `unit.destroy` (the ed teardown/sync) still runs explicitly on true deletes
  (`clear_all`/`delete`/`claim_name`/reload) — those call sites already do, or
  can, call it directly. This is the load-bearing part to get right: every
  current path that relies on `removed → remove_from_scene → unit.destroy` must
  instead call `unit.destroy` itself (which then frees owned containers + syncs
  DESTROY; the node follows via ORC). Needs careful in-world validation of
  level reload, single delete, and multiplayer mirror teardown.

This removes move-detection entirely (a move never destroys because the unit is
never reclaimed), at the cost of auditing every teardown call site. Bigger, but
no special cases.

## Test prerequisite (do this first)

**`test_world` corrupts tracked sources on this branch.** Running it
deletes/rewrites files under `tests/worlds/` because PR #62's `--temp-workdir`
isolation fix isn't on `course`/`adopt-lifecycle` yet. Before any in-world adopt
work, either land/rebase onto PR #62 or cherry-pick the `--temp-workdir` commit.
(Recover from an accidental run with `git checkout -- tests/worlds/`.)

## Test plan for adopt (once unblocked)

Headless, per the handoff's MCP driving, against a **/tmp scratch level** (never
a tracked world):

1. Spawn a platform build that moves (`forever:` translate), and a bot at root.
2. `me.adopt(bot)` from the platform script (or `bot`-targeted).
3. Poll the bot's **world** position across frames → it tracks the platform
   (bot-ferry: bots don't auto-ride, so this is the real win).
4. `bot.release` → bot re-roots to `state.units`, stops riding, doesn't jump.
5. Assert neither adopt nor release teleports the bot (transform conversion).
6. Re-run `test_unit`/`test_vm` + (on an isolated tree) `test_world` x3 to
   confirm normal spawn/teardown is unregressed by the two guards.

## Risks / watch-items

- **Synced-change ordering** on the main thread: membership ADD/REMOVE, the
  `GLOBAL` flag change, and the `transform_value` change arrive as separate
  synced ops; the reparent (set_global) and transform must converge regardless
  of order. Validate with the platform already moving.
- **The voxel-teardown flake**: bulk-spawn `test_world` failed 1/5 with
  `VoxelMemoryPool: 4294967294 blocks still used` (an over-decrement) then
  passed 4/4. Pre-existing (baseline shows the same class of at-exit leak
  noise); not caused by the cursor change, but worth a separate look since a
  voxel double-free could interact with lifecycle changes.
- **`release` requires re-rooting** an adopted unit (`platform.units` →
  `state.units`) — make sure the root `state.units` add path (ownerless
  collection) sets up `parent = nil` and GLOBAL correctly.
