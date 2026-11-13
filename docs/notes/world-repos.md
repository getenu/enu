# World repos: source, state, and git

> Status: **direction, not started.** Settled in discussion on 2026-11-13, ahead
> of the next data pass. Replaces the direction in `durable-persistence.md`
> (which predates voxel frames and bakes); its restart-and-checkpoint script
> model still stands and is summarized below. Companions: `multiplayer-discovery.md`
> (identity, approval, connecting) and ed's `decentralization-and-scaling.md`
> (authority, failover, scaling).

## Goal

A single git repo is enough to start or join a multiplayer enu world. If you
have write access to the repo, you can join; the repo carries the public ids
needed to connect. Joining a live world restores it as it was, not just as it
was designed. Running costs stay close to zero: someone else hosts the repo,
and our own infrastructure is at most a small rendezvous/relay server.

Ed does almost all of the persistence. Enu labels its models and supplies a few
hooks, and the files still look much like today's level format.

## Two layers: source and state

The split is by who owns the data, not what kind of data it is.

**Source** is what people and agents author: human-readable, diffable, meant to
be edited. Roughly today's level format:

- `level.json`, each thing's JSON (start transform, start color, flags,
  hand-placed edits), and its script;
- frames for authored animation (already `.bin` sidecars past 1000 blocks).

Editing a source file means "change the design": the thing reloads, as the
file watcher does today. Humans and agents work the same way: they edit
source.

**State** is what the running world produced:

- current transforms;
- things spawned by scripts;
- computed voxels;
- player records;
- script checkpoints;
- the op log between saves.

It's stored efficiently and isn't meant for hand editing.

**Bakes** are derived but self-validating (keyed by a hash of their inputs), so
they're safe to commit with source. They're binary and live outside the thing
JSON (one file per bake key is the git-friendly shape; see below).

Enu's models already split this way in places: `start_transform` is source and
`transform` is state, `start_color` and the current color likewise. So the work
is mostly labelling fields, not restructuring.

### Labels are per field

Each field carries a persistence class: `source`, `state`, or `ephemeral`. A
pragma on the type sets the default for all its fields, and a field pragma
overrides it, e.g. `type Thing {.persist: state.}` with `start_transform
{.source.}` and `collisions {.ephemeral.}`. The registry reads these at compile
time, like the layout hash. This is separate from the sync flags: plenty of
`SYNC_LOCAL` data is ephemeral, and sync never implied persistence.

### Keeping state honest when source changes

Each thing's state records a hash of the source it came from (the trick bakes
use). On load, state whose source changed is dropped, with its dependents, and
the thing starts fresh from source. "I edited the file while the world moved
on" becomes a rule, not a merge.

### Two load modes

- **Reset:** source only. Today's behaviour; what shipped tutorials want.
- **Resume:** source, then state. A repo can ship without state (a tutorial) or
  with it (a live world).

## What ed owns

- A field-named codec for registered types (the nim-serialization step in ed's
  plan).
- The per-field persistence classes above.
- Layout hooks, so enu can say: a thing is a document at `data/{id}/{id}.json`;
  its code is `scripts/{id}.nim`; edits use the compact array encoding; frames
  and bakes go to `.bin` sidecars. The format stays enu-shaped, but ed reads and
  writes it.
- Watching source files and turning edits into ops (enu's file watcher moves
  into ed).
- Loading both layers, with the source-hash check.

Enu keeps the labels, those hooks (load order, scripts, bakes), and its policy
for what reset means.

## Scripts restart from the top

VM-state resume stays rejected (`durable-persistence.md` has why), so on resume
every running script starts over. Two consequences:

1. **Spawns must be idempotent.** If spawned things come back from state and
   their spawner runs `.new()` again, everything doubles. So spawned things get
   stable ids (spawner plus which call created them; instance ids are nearly
   that already) and `.new()` becomes get-or-create, the planned `init`
   behaviour. A restarted spawner adopts the restored instance, position and
   all.
2. **What to restore depends on the script.**
   - A thing whose script finished (most builds) restores fully: computed
     voxels and all, no re-run. The big win.
   - A thing whose script is still running resets to its start and runs again,
     unless it opts into checkpoints and says how to resume.
   - A thing with no script restores its state as is.

The checkpoint API (a durable per-thing `state[...]`, read back on restart) and
the dependency-ordered VM rebuild from `durable-persistence.md` carry over.

## Git

### Branches

- **The source branch** is what people and agents edit. Normal history, where
  diffs mean something.
- **The state ref** holds live worlds. Each state commit is the whole world:
  the source files plus a `state/` directory. Its parents are the previous state
  commit and the source commit it was built from. Git stores the source files
  once, shared with the source branch, so this costs nothing extra.
- **Saving** a live world commits to the state ref. When source has moved on,
  the new state commit merges it, which is the same moment the running world
  reloads the edited things.
- **Joining** a live world checks out the state ref: a consistent snapshot of
  source plus state from one moment, and git's ancestry says which source it was
  built on.

The per-thing source hashes are the safety net: if the two get out of step, a
thing whose source changed under its state starts fresh. The worst case is a
partial reset, never corruption.

Open: whether the state ref keeps its history or is periodically replaced by a
parentless commit to bound repo size, and how often a live world saves.

### Making binary state git-friendly

How git stores data: whole files, compressed, with identical content stored
once; changed files are stored again in full until packing, which stores
similar files as deltas; and changing a file rewrites the directory listings on
its path. So:

1. **Many small files keyed by something stable**, not one big file: one per
   object, one per voxel chunk, one per bake key. Unchanged pieces cost nothing,
   so a save only stores what changed. This matters more than append-only.
2. **Byte-for-byte deterministic encoding.** Same state, same bytes: stable
   ordering, no timestamps, no hash-table iteration order.
3. **No compression inside the files.** Git compresses already, and
   pre-compressed data defeats its delta packing (snappy-packed chunks need a raw
   form on disk).
4. **Fan large directories out** into hashed subdirectories, like
   `.git/objects`, so each change rewrites only small listings.
5. **Logs as immutable segments**, never a growing file. Ed's store already
   rotates segments and seals snapshot directories.
6. **Modest file sizes.** GitHub refuses files over 100 MB; a world of many
   small files avoids that naturally.

No LFS: it complicates hosting for little gain once the format follows these
rules.

## A repo as a multiplayer world

Write access is membership. Pushing a ref is an atomic compare-and-swap (push
with lease), so:

- **The host claim is a ref**, e.g. `refs/enu/host`: the host's public id, an
  address hint, and an epoch. Claiming the world is pushing it with a lease;
  only members can.
- **Members' public keys live in the repo**, the git-committed form of
  `authorized_peers` from `multiplayer-discovery.md`.
- **Connecting** uses free infrastructure where possible: public STUN for
  address discovery, and the repo itself can carry the address exchange for
  hole punching (a joiner pushes its address, the host reads it; slow, but fine
  for a join). The discovery doc's small rendezvous server remains the fallback
  for punching and relaying when NATs refuse.

Cautions: git hosts rate-limit operations, so pushes coordinate joining and
hosting only, never gameplay; and anyone who can read the repo can see the
addresses in it, a conscious choice under the cooperative-trust model.

## Open questions

- How a state commit and a host claim interact when the host changes (the old
  host's unsaved state, the new host's base).
- Offline writes: today they're overwritten on reconnect. Replaying them as
  `REJECT_STALE` writes would check them against what happened meanwhile (ed's
  `decentralization-and-scaling.md`).
- Store granularity: per level (today's unit of save) vs per world.
- Whether bakes stay in source for shipped levels, or move to state with a
  rebake on reset.
