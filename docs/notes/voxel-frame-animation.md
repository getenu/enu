# Voxel frame animation

Multi-frame voxel animations as an engine feature: pose a unit's voxels (via
script, external client, or hand edits), save the state as a frame, repeat,
then play the frames back. Sized for animated animals and small units first,
but designed so the same mechanism scales to large builds — the animated-sea
prototypes (`bin/demos/demo_sea.nim`, `SEA_FRAMES`) are the stress case.

Status: design + prototypes (2026-07-04). Post-0.3 feature. Frames will be
driven from client apps and VM scripts first; UI later.

## What a frame is

**A frame is a packed chunk-set** — `{chunk_id -> SnapshotData}`, the same
RLE/sparse encoding the sync layer and codecs already use (1 B/voxel for
named colors, 2 B for wide static-palette values; see `models/voxels.nim`).
Frames are *data*; meshes are *cache*. Never the reverse:

- Meshes are derived, viewer-local, and partial (blocks page with view
  distance), so a saved mesh can't represent a large unit.
- Meshes go stale under library re-bakes (e.g. future env palette remaps).
- Data frames keep semantics: collisions, `block_color_at`, hand-editing a
  frame later, diffing.

Frames snapshot the merged `local_voxels` state, so script draws, external
draws, and MANUAL hand edits all compose before `save_frame`.

## Storage

- Frame 0 (and every Kth frame, video-GOP style) is a full snapshot; frames
  between are sparse deltas against the previous frame (`FMT_SPARSE_DELTA16`).
  Producing a delta from two snapshots is: decode both arrays, diff, encode —
  the codecs exist. Measured on the sea: 10–20% of water voxels change per
  frame at 8 fps, so deltas run 5–10x smaller than snapshots; an unchanged
  chunk diffs to ~nothing, so mostly-static builds pay almost nothing.
- Persistence: sidecar binary files (`data/<id>/frames/NNN.bin`), gzip-friendly,
  NOT base64 inside the unit JSON. The JSON carries metadata: format version,
  frame count, fps/loop defaults, content hashes, and the **static palette as
  a hex array** (packed values reference palette indices).
- The same threshold idea applies to non-animated builds: past a few thousand
  voxels, persist packed chunks in a sidecar instead of the per-voxel JSON
  edit list (~30-40x smaller before compression). Small builds keep the
  readable, diffable JSON.

## Sync

Frames sync once, as data — ideally LAZY per (frame, chunk) so partial
replicas page only what they can see. Playback syncs only a tiny state:
`(frame_index, fps, playing, loop)`. Replicas render locally from their frame
data; no voxel traffic during playback. The server owns playback advancement;
clients (and the UI later) just write the playback state.

## Rendering

The per-chunk **frame-mesh cache** is the heart of the feature:

- Key the cache by `(chunk, content_hash)`, not `(chunk, frame_index)` — the
  sea's island/beach chunks are identical across all 32 frames and collapse
  to one mesh; a wiggling ear caches ~2 meshes for the ear chunk and 1 for
  everything else.
- On tick, a chunk displaying frame n: cache hit -> visibility swap
  (microseconds); miss -> build + cache. A chunk entering view shows a static
  frame until its meshes warm (build one frame-mesh per tick; after one loop
  it joins the animation). Eviction rides block paging, so memory is bounded
  by loaded chunks x distinct frame meshes — view-distance-bounded, not
  world-size-bounded. Fog ends at 200 m and the shader discards at 230, so a
  500x500 ocean's live zone is a ~150-200 m disc per viewer regardless of
  ocean size.
- Temporal LOD when needed: full frames near the viewer, fewer frames
  mid-distance, static beyond.
- Meshing needs no engine change: `VoxelMesher.build_mesh(buffer,
  materials)` is scriptable (and its scratch is `thread_local`, so
  main-thread baking never races the meshing threads). Frames render as
  plain `MeshInstance` children of the terrain node whose `.mesh` pointer
  swaps per flip. The instances inherit the node transform, so scaled
  builds animate correctly — which retired M1's scale-display bug.
- Hiding the live meshes IS the one engine touch (owned fork, godot_voxel
  `1b7f0ea`): `VoxelTerrain.set_render_blocks_visible(false)` hides every
  render mesh of that one terrain — data, collisions and children
  untouched, newly meshed blocks respect the flag. Per-node by
  construction, so sibling units sharing a Shared (spawner clones) are
  unaffected when one displays frames. A first cut used a discard shader
  swapped onto the live materials instead; it worked but leaked to every
  unit rendering with those Shared materials. Frame meshes bake with the
  live material objects, so glow, highlight, god mode and env changes
  apply to them exactly as to live meshes.

Cost cutters, measured against the sea prototypes:

- **No collision on frames.** `VoxelMeshBlock::set_collision_mesh` builds a
  `ConcavePolygonShape` trimesh duplicating the whole render surface (often
  2-4x the render mesh, plus BVH build time) — only the base/current frame
  should ever collide, and animation frames never.
- **Sheet culling.** A unit-level `sheet`/`cull_down_faces` hint skips -Y
  faces at mesh time. The sea slab has air beneath it, so every column emits
  an invisible underside today; culling it roughly halves water geometry.
  (Far future: `HeightMapShape` collision for heightfield-like units.)

## Stepping stone: freeze-while-hidden (no engine change)

`VoxelTerrain` drives all streaming/meshing/unloading from plain
`NOTIFICATION_PROCESS` (`voxel_terrain.cpp`), so `set_process(false)` freezes
a terrain in place with meshes resident — and it's orthogonal to visibility
(process on + hidden = warming quietly; process off + visible = displayed,
frozen). That makes the frames-as-sibling-units flipbook viable at mid sizes:
warm each frame (process on, hidden), freeze all, cycle visibility. Measured
without freezing: a 60 m x 32-frame ocean works (0.57 GB, fully meshed,
seamless); 250 m x 32 thrashes — every frame-unit streams around every viewer
regardless of visibility, which is exactly the flaw the real feature removes.

## API (v1: client + VM; UI later)

    build.save_frame()            # append a frame (raises past 64 frames)
    build.save_frame(at = 3)      # overwrite frame 3 in place
    build.load_frame(3)           # restore frame 3 into the live voxels
    build.frame = 2               # display-only; -1 = live state
    build.frame_count
    build.delete_frame(3)         # later frames shift down
    build.clear_frames()          # explicit — frames persist across script
                                  #   re-runs (hand-edit flow: pose, run a
                                  #   script calling save_frame, repeat)
    build.play_frames(fps = 8.0, loop = true)
    build.stop_frames()

Script reset stops playback and drops the display but keeps frames;
programmatic animations call clear_frames() first. The 64-frame cap
(MAX_FRAMES) keeps an unguarded save_frame loop from growing forever.

## Milestones

1. **M1 — data frames end-to-end** (landed 2026-07-05): frame storage on
   Build (synced), save / set / count / play with server-side advancement;
   frame switch re-renders locally per side (fine for small units); client +
   VM APIs; unit + world tests. Known issue: frame *display* doesn't remesh
   on scaled builds (data provably updates; the mesh-update scheduling drops
   it — same scale/coordinate family as floor_at ignoring scale). Works at
   scale 1.
2. **M2 — frame-mesh cache** (landed 2026-07-05, no engine change): frames
   display as baked meshes via `VoxelMesher.build_mesh` on MeshInstance
   children — zero voxel writes and zero remeshing per flip. Cache keyed by
   chunk content hash mixed with all 26 neighbors' (border culling stays
   correct, identical chunks dedupe across frames); baking is time-boxed
   (8 ms/tick) with `frame_bake_pending` continuation, so big builds warm
   over the first loop instead of hitching. Live voxel data is never
   touched: collisions, queries and the return-to-live path all read the
   real state, and scaled builds animate (M1's scale-display bug is gone).
   Measured: small builds swap instantly; a 120 m x 32-frame ocean (68K
   voxels/frame, ~450 chunks) warms ~2-3 min under live playback then
   animates at 8 fps with zero main-thread slow-tick warnings. A 250 m
   ocean's working set (~33K meshes) exceeds the 16384-mesh cache cap, so
   it stays on the live state (graceful) — that size needs M3's temporal
   LOD/eviction/sheet culling. The `"frame playback"` / `"frames showing"`
   log pair shows whether a build has swapped in yet.
3. **M3 — storage + polish**: keyframe+delta compression, sidecar
   persistence, temporal LOD, sheet culling, UI.

## Prototype numbers (2026-07-03/04, M2-sizing evidence)

- 250 m sea, 32 frames as units: generation + sync fine (paced bursts —
  unpaced floods drop the client session); mesher thrash kills it.
- 60 m x 32 frames: works, 0.57 GB total, ~2.5 min generation, loops
  seamlessly at 8 fps with dispersion-snapped wave speeds.
- Palette work pays off here: all frames share the unit palette, so a
  320-color animated build bakes its library entries exactly once.
