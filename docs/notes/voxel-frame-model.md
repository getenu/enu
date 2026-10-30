# Voxel frames: one model

Plan for reworking #113 so a build's frames are the build's voxels, rather
than snapshots kept beside them.

## Why

Today a build has two representations of its blocks:

- **The live voxels.** These are `packed_chunks` / `chunk_deltas` on the
  Build, the `Shared` edit tables, and the `VoxelStore` that decodes them.
  Everything reads and writes these: drawing, hand edits, the computed and
  manual rules, collisions, saving and the normal render path.
- **Frames.** `frames: EdTable[int, FrameData]` holds whole-build snapshots as
  packed chunks, and playback renders them with a second renderer
  (`FramePlayer`).

The current frame lives in the first one and every other frame in the second,
so we keep copying between them:

- Switching frames packs the live voxels into a `FrameData`, then unpacks the
  next frame back in. Rebuilding the edits on the way in happens block by
  block (`load_live_frame`).
- Hand edits go to the live voxels while playback shows a stored frame, so a
  click has to stop the animation (`stop_for_edit`).
- Saving has to treat the current frame specially (`saved_frame`).
- Rendering has a live path and a flipbook path, with `current_frame = -1`
  switching between them.
- Main has no `local_edits`, so it can't switch frames itself.
- `FrameData` comes out of the synced table by value, which copies megabytes,
  so `FramePlayer` keeps its own deep copies to avoid that.

## The model

A build is a list of frames, and every frame is stored the same way. A
single-frame build is just a build with one frame.

### Identity and order

- Each frame has a stable `FrameId` (an int that is never reused within the
  build).
- `frame_order: EdValue[seq[FrameId]]` maps index to id. It is replaced whole
  on change, because ed's positional seq ops don't sync order-safely.
- Inserting, deleting and reordering frames only edits `frame_order`. No
  chunk data moves. Copying a frame copies its rows under a new id.

### Synced tables, keyed by frame

| table | key | holds |
|---|---|---|
| `packed_chunks` | `(FrameId, chunk)` | the frame's blocks, computed and manual |
| `chunk_deltas` | `(FrameId, chunk)` | deltas since that snapshot |
| `edit_snapshots` / `edit_deltas` (on `Shared`) | `(thing_id, FrameId, chunk)` | the frame's manual blocks and holes |

The `frames` table and `FrameData` go away as synced state. `FrameData` stays
only as an in-memory and file format.

### Which frame is which

- `frame` (synced): the frame the script draws into. When nothing is playing,
  it's also the frame on screen.
- `shown_frame` (synced): the frame on screen. While playing, playback moves
  it; otherwise it follows `frame`.
- Draws go to `frame`. Hand edits, collisions, click raycasts and
  `voxel_info` from the UI use `shown_frame`.

There is no `-1`, and no state where the screen shows something other than a
frame.

### VoxelStore

- The chunk cache is keyed by `(FrameId, chunk)`. Main keeps a small LRU; the
  worker is unbounded, as today.
- Point reads and writes take a frame. Build-level procs pass `frame` or
  `shown_frame`.
- `local_edits` becomes a lazily decoded per-`(FrameId, chunk)` cache over
  the edit tables, and both threads build it the same way. Main can then
  apply the computed and manual rules on its own, which removes the
  asymmetry where only the worker knows the edits.
- Pending buffers and paced flushing stay as they are, keyed by frame.

### Script runs

The rules we agreed on stay the same:

- A run starts on frame 0. For every frame, it drops the computed blocks by
  rebuilding each chunk from that frame's edits only. This is a chunk-level
  rewrite, with no per-block work.
- Holes work per frame. `unmark_holes` at reset and `collect_garbage` at the
  end walk every frame's hole edits.
- `frame = n` only retargets drawing, and grows `frame_order` if `n` is past
  the end. Nothing is copied.

### Rendering

There is one path: the terrain shows `shown_frame`.

- Deltas for the shown frame repaint in place, as live deltas do today.
- Changing `shown_frame` is a flip, using the existing `FramePlayer`
  machinery: mesh cache by content key, staged atomic commit, temporal LOD
  and baking from data. It reads chunk bytes straight from the synced tables
  by `(FrameId, chunk)`, so no `FrameData` copies are needed.
- Deltas for a frame that isn't shown invalidate that chunk's content key,
  and the next flip picks up the change.
- Block prefill (`prefill_bytes`) serves the shown frame.

### Persistence

- A build with one frame and fewer than `EDITS_SIDECAR_THRESHOLD` manual
  blocks keeps its edits in the unit JSON.
- Otherwise each frame's manual blocks go to `data/<id>/frames/NNN.bin` in
  `frame_order` order. A keyframe is written every 8 frames, with deltas in
  between, as today.
- The JSON meta keeps `count` and the shown/target frame.
- Loading installs each file a chunk at a time, straight into the edit
  tables and the chunk tables (`adopt_edit_chunks`, generalized per frame).
  Big terrain loads as fast as `edits.bin` does today.
- `edits.bin` is still read for migration and is replaced by `frames/000.bin`
  on the next save.
- Computed blocks are never written, except by `bake` (#107).

### Network

- Remote clients page `(FrameId, chunk)` the way they page chunks today.
- A visible chunk requests the frames in its build's playback range.
  Temporal LOD could later limit far chunks to the frames they actually
  show.
- Playback syncs only `shown_frame`, `fps`, `loop`, `first` and `last`, as
  today.

## What goes away

`store_live_frame`, `load_live_frame`, `pack_frame` / `load_frame` as the
switching mechanism, `saved_frame`, `stop_for_edit`, `current_frame = -1`,
the synced `frames` table, `FramePlayer.frame_data` copies, and the
live-versus-flipbook branches in `build_node.nim`.

## Phases

Each phase lands with its tests green.

1. **Store.** `FrameId` keys, `frame_order`, a per-frame chunk cache and edit
   cache, and frame-aware point ops. A single-frame build behaves exactly as
   it does today. Unit tests: the existing block-rules and packing tests run
   on frame 0, plus per-frame isolation tests.
2. **Builds and VM.** Frame ops become order and table ops. Run start drops
   computed blocks per frame. Holes work per frame. The VM API (`frame`,
   `me.frames` as a seq, `play`) is unchanged. Tests: block_rules frames
   suite, `build_frame_test`.
3. **Renderer.** One path driven by `shown_frame`. `FramePlayer` reads the
   tables. Hand edits go to the shown frame while playing. Check in the world
   on the welcome water and gulls (release build).
4. **Persistence.** Per-frame files, chunk-level load, `edits.bin`
   migration. Tests: serializers, plus a save and reload of the tutorial in a
   real instance.
5. **Network paging** per `(FrameId, chunk)`. Check with a second instance
   connected.
6. **Bake (#107)** on top.

## Decisions

- Frame ids are stable runtime keys. Scripts only ever see positions:
  `me.frame` and `me.frames` behave like an indexed seq, and a delete shifts
  the later frames down. Ids are never saved: files are written by
  position, and loading assigns fresh ids 0 ..< n.
- A remote client pages every frame of a visible chunk.
- This replaces the earlier #113 frame code rather than landing on top of it.

## Status

Phases 1–4 are in #113; phase 5 needs no more than requesting every frame's
rows for a chunk in view (`on_block_loaded`). Decisions made on the way:

- The decoded edits (`local_edits`) fill lazily per chunk from the edit
  tables. Saving, hole passes and frame copies read the packed rows, so a
  build of hand-placed frames (the welcome water: ~half a million blocks a
  frame) isn't decoded to find nothing.
- A load adopts every frame but the current one; the build's
  `restore_edits` adopts that one, as for a single-frame build.
- Older frame files load with their computed blocks dropped (a script draws
  them again) or, for a build with no script, kept as hand-placed blocks.
  Such builds are marked dirty so the load-end save rewrites them.
- Frame files are rewritten only when `frames_hash` (every frame's edit
  rows, by index) differs from the last save or load.

Open: main's lazily decoded edits aren't invalidated when the worker
changes them afterwards (and the worker's not between refreshes), so a
click can be judged against stale edits.
