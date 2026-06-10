# Reload-churn livelock — diagnosis (DESTROY side of the reincarnation race)

Repro: `reload-churn-repro.sh` (other agent). Rapidly rewrites + `touch`es one
build's JSON, alternating a valid and a *compile-error* script. Each mtime bump
forces worker.nim's mtime reload (`state.units -= unit; load_unit_from_json`) =
destroy+recreate of the **same unit id**. Done fast, incarnations overlap.

## It reproduces — but it's timing-flaky
With my committed fixes (find_ref + synced Shared + hoist) in place: **0 invalid
on a single 10-cycle run, but it fails within 1–6 iterations of looping 8-cycle
churn** (caught 1620 / 3491 invalid). So the other agent was right — *not* fixed;
just dodged by machine speed. Once it fails it **livelocks** (see below), so a
single pass means nothing.

## Mechanism (confirmed)
The unit/build is an EdRef whose **id is reused** every reload (`build_churn_repro`
— it's the persistent/file identity). Under churn:

1. Worker destroys incarnation N and creates N+1 (same id). A **stale/echoed
   `DESTROY(build_churn_repro)`** for N lands on the node *after* N+1 exists.
2. `DESTROY` is **by id**, and N+1 is the current holder of that id — so it
   destroys **N+1** (the live one). Then `EdRef.destroy → destroy_owned(
   build_churn_repro)`, and `owned_by[build_churn_repro]` (keyed by the **reused
   bare id**) now holds **N+1's** generated-id containers (`units`, `code`, …) —
   so the cascade tears down the *live* incarnation's fields.
3. N+1 is still in `state.units`, so `walk_tree` (game.nim:98) reads its now-dead
   `.units`, and `build_node:296 process` reads its dead `.code` → `Ed invalid`
   every frame.

## Why it livelocks (amplifier — see the `sample` profile)
Each `Ed invalid` is **logged**, and the log path `+=` to a reactive state
collection → `trigger_callbacks` → the **in-game console** (`appendBbcode` to a
RichTextLabel). Rendering the ever-growing console pins the main thread. So a
transient dead read becomes a permanent stall (worker heartbeat freezes).

## Why the earlier fixes don't cover it
`find_ref` fixed the **CREATE** side (dedup must not resurrect a destroyed
instance). This is the **DESTROY** side: a stale DESTROY hitting the live
incarnation. ed can't tell it's stale because:
- `DESTROY` is by id; N and N+1 share the id (no **generation** to disambiguate).
- The LSN idempotency (`subscriptions.nim:1158`) only drops `lsn > 0` ops;
  cascade / echoed DESTROYs are **unordered (lsn 0)** and always apply.
- An "is this the current ref_pool instance?" check doesn't help — the stale
  DESTROY destroys N+1, which *is* current at that instant.

So this is the destroy+recreate-same-id race the prior decision called "holding
it wrong" — the previous session made *clean/drained* reloads work; *overlapping*
(churn) reloads stay racy.

## Fix options (architectural — needs a call)
- **(a) ed: incarnation generation.** Stamp each incarnation; DESTROY carries the
  target generation; drop stale DESTROYs. Robust, fully supports reuse, but a real
  ed feature ("ed has no generation to disambiguate").
- **(b) ed: order *all* destroys.** Propagate lsn/op-source through the cascade +
  the collection-remove destroy so stale ones are dropped by idempotency. Touches
  op-stamping broadly.
- **(c) enu: fresh ed id per incarnation.** Keep the logical/file identity but give
  each reload a fresh *ed* ref id → no reuse, no race. Now *more* feasible because
  the hoist made voxels reconnect by reference (no derived-id dependency) and
  Shared is synced — but `unit.id` == the logical id is used widely, so separating
  the two is itself a sizeable enu change.
- **(d) surface it** (per the prior "holding it wrong" framework): detect + raise
  (dev) / error (release) on destroy+recreate-same-id under sync. Hard to do
  without false-positiving the *clean* reloads that already work.

The amplifier (logging a dead read into a reactive console → livelock) is worth
hardening **regardless** — a dead-object read in a per-frame path shouldn't be
able to wedge the editor.

Status: reliably reproduced + root-caused; probes removed; nothing committed.

## Implementing (a): incarnation generations

### Ruled out — lightweight "registry identity" guard
First tried the cheap version: in `EdRef.destroy`, skip `destroy_owned` if a
*different* instance is now registered under the id (superseded). It made it
**worse** (16/16 fail) — because `owned_by[id]` **conflates both incarnations'
objects under the one reused id**: skipping the cascade for a superseded N
*leaks* N's containers, and not skipping destroys N+1's. destroy_owned literally
can't tell N's objects from N+1's. So we need a real per-object generation.

### Design (synced owner-generation)
- **`EdRef.gen: int`** — the incarnation's generation, a serialized field so it
  rides the ref's sync (replica gets the authority's value).
- **Owner-gen on owned objects** — each owned object records its owner's gen at
  creation. Carried on the **container CREATE** (new `Message.owner_gen`, beside
  the existing `owner_id`) so it's authoritative regardless of arrival order
  (containers arrive *before* their owner on a replica — local stamping would be
  wrong). For `set_owner`'d EdRefs (e.g. `shared`), pass the gen into `set_owner`
  (re-derived locally on each ctx using the synced `owner.gen`).
- **`destroy_owned(ctx, owner_id, gen)`** — destroy only owned objects whose
  recorded owner-gen == `gen`. `EdRef.destroy(self)` calls it with `self.gen`.
- **Assignment** — `next_incarnation(ctx, id)` bumps a per-id counter
  (`EdContext.incarnation`) and sets a `current_owner_gen` threadvar for the own
  scope; enu's `Build.init`/unit ctors call it once at construction and set
  `self.gen`. Authority-assigned; replicas read the synced values.

Result: a stale `DESTROY` for incarnation N carries gen N; on a replica where the
live owner is N+1 (gen N+1), `destroy_owned(id, N)` matches only N's (already
gone) objects and leaves N+1's intact.

Wrinkle to handle: `owned_by[owner_id]` mixes containers (gen via Message) and
`set_owner`'d EdRef members (gen via the local `set_owner` call) — the filter
must read both. ~10 integration points across ed + enu.

### Implemented — destroy-side works, CREATE-side duplicate remains
Built the full destroy-side: `EdRef.gen`, `Message.owner_gen`, `EdContext.{
incarnation, owner_gen}`, `current_owner_gen` threadvar + `own(id, gen)`,
`next_incarnation`, container stamping (`initializers` + `process_message` sync),
`destroy_owned(owner_id, gen)` filter, `set_owner(..., gen)`, and enu's
`Build.init` minting the gen. **ed suite 133 green; churn went from failing at
iter 1–6 → 8 clean iters then failing at 9.** Real improvement, but not a full
fix.

The remaining failure is a **same-incarnation duplicate**, which gen filtering
*cannot* catch: the destroy DBG showed a `gen=N` `destroy_owned` tearing down
live `gen=N` containers while a *different, live, non-destroyed* `gen=N` build
still reads them. So two instances share the same gen and the same container ids
— destroying one kills the other's containers.

Attempted a CREATE-side **destroyed-gen tombstone** (`EdContext.destroyed_gen`,
set in `EdRef.destroy`, checked at `type_registry` registration to flag a stale
incarnation inert) + skip-destroyed in `walk_tree`/`build_node`. It **did not
help** (identical 8-then-fail-at-9), so the duplicate is *not* a simple
destroy-then-recreate the tombstone sees — likely a gen-sync-timing gap (the
ref's `gen` not yet set when registered, or `find_ref` creating the second
instance on a path the tombstone misses). Needs more investigation; possibly the
collection-delta / `find_ref` dedup path itself.

Status: destroy-side generations implemented + working for the common race (ed
green); CREATE-side same-gen duplicate remains. All WIP uncommitted.
