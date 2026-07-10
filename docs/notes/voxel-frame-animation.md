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
draws, and PERSISTED hand edits all compose before `save`.

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
- Keys are shell-aware: the mesher culls border faces (and bakes AO)
  against neighboring blocks, so the key hashes the chunk's 16³ content
  plus a 1-voxel shell gathered from its frame neighbors (the padded 18³
  region). Identical keys then imply identical meshes; central-only keys
  reuse meshes with wrong borders. Memory is bounded by loaded chunks x
  distinct frame meshes — view-distance-bounded, not world-size-bounded.
  Fog ends at 200 m and the shader discards at 230, so a 500x500 ocean's
  live zone is a ~150-200 m disc per viewer regardless of ocean size.
- Temporal LOD (landed with M3): each chunk displays an *effective*
  frame by distance to the nearest paired viewer — full rate inside 96 m,
  every 4th frame to 160 m, a static frame beyond. Quantized frames are
  just other content keys, so the cache, miss set and blocking playback
  need no special cases; distant chunks simply flip less and collapse to
  far fewer unique meshes. Bounds the mesh cache by the near disc rather
  than the whole loaded area.
- The terrain itself is the display. A flip writes each changed chunk's
  voxel data (`set_block_voxel_data`, no remesh) and, for cached content
  keys, stages the mesh; the visible change is one atomic commit pass per
  flip (mesh pointer swaps — microseconds each), prepared ahead during
  the previous interval so cadence stays exact. Data holds the displayed
  frame, so collision and queries match the screen, and scaled builds
  animate correctly (the terrain inherits the node transform).
- Misses bake FROM DATA, not from the world: the receiver assembles the
  padded 18³ buffer itself — the chunk's frame bytes plus a shell from
  its neighbors' frame bytes — and submits it to the engine's worker pool
  (`request_frame_mesh`); the result returns via `frame_mesh_baked`
  tagged with the content key it was built for. Bakes are pure functions
  of the submitted bytes, so nothing can be misattributed or poisoned,
  no matter what any neighbor currently displays.
- Playback is free-running: it never waits for meshing. A chunk whose
  target isn't cached keeps its previous mesh (stale, never a hole — the
  generator keeps one always-solid layer) and joins in sync on the flip
  after its bake lands. Movement and newly loaded chunks therefore never
  slow the animation. Warm-up converges at worker throughput; each
  (chunk, content) pair bakes at most once.
- `sealed_frames` (per unit, on by default): bake with an air shell, so
  every chunk mesh carries its own boundary skin — any mix of displayed
  frames is visually closed, and keys collapse to the chunk's own bytes
  (better dedup: the 250 m sea needs ~6 K meshes instead of ~15 K).
  Costs ~a third more (invisible, backface-culled) border quads and
  neighbor-aware AO at chunk edges. Off: real-shell bakes, shell-aware
  keys, fewer quads and exact AO, but chunks displaying different frames
  (temporal LOD bands, catch-up) can show transient seams.
- Frame meshes bake with the live material objects, so glow, highlight,
  god mode and env changes apply to them exactly as to live meshes.
  (Earlier iterations — a main-thread baker, an async paste-and-capture
  pipeline, then blocking apply-and-harvest — all coupled bake
  correctness to live terrain state; every gating scheme they needed,
  version gates, pipeline drains, cleanliness checks, was a symptom of
  that coupling. Baking from data removed the class.)

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

    build.save()                  # append a frame (raises past 64 frames)
    build.save(at = 3)            # overwrite frame 3 in place
    build.load_frame(3)           # restore frame 3 into the live voxels
    build.frame = 2               # display-only; -1 = live state
    build.frame_count
    build.delete_frame(3)         # later frames shift down
    build.clear_frames()          # explicit — frames persist across script
                                  #   re-runs (hand-edit flow: pose, run a
                                  #   script calling save, repeat)
    build.play(fps = 8.0, loop = true)
    build.stop()

Script reset stops playback and drops the display but keeps frames;
programmatic animations call clear_frames() first. The 64-frame cap
(MAX_FRAMES) keeps an unguarded save loop from growing forever.

## Milestones

1. **M1 — data frames end-to-end** (landed 2026-07-05): frame storage on
   Build (synced), save / set / count / play with server-side advancement;
   frame switch re-renders locally per side (fine for small units); client +
   VM APIs; unit + world tests. Known issue: frame *display* doesn't remesh
   on scaled builds (data provably updates; the mesh-update scheduling drops
   it — same scale/coordinate family as floor_at ignoring scale). Works at
   scale 1.
2. **M2 — frame-mesh cache** (final architecture 2026-07-06): blocking
   apply-and-harvest, described under Rendering above. Engine additions
   (owned fork): `set_block_voxel_data` (full-block data write, optional
   remesh), `set_block_mesh` (direct mesh assignment), refcount-guarded
   in-place ArrayMesh reuse. Measured: a 120 m x 32-frame ocean (68K
   voxels/frame, ~275 loaded chunks) warms in ~25 s under playback, then
   animates at 8 fps with `missing=0, harvests=0` in the frame stats,
   zero slow-tick warnings, and ~1.4 GB RSS (5,643 cached meshes). The
   `"frame warm-up"` / `"frame stats"` log lines show warm-up progress
   and steady state.
3. **M3 — storage + polish** (landed 2026-07-06 except UI): sidecar
   persistence (`data/<id>/frames/NNN.bin`, keyframes every 8 frames +
   per-chunk sparse deltas; fps > 0 at save resumes playback on load; the
   unit JSON carries count/fps/loop and the static palette in allocation
   order), the same sidecar idea for big non-animated builds
   (`data/<id>/edits.bin` past 1000 edited voxels), sheet culling
   (`cull_down_faces` on Build — skips downward faces at mesh time), and
   temporal LOD (above). UI is post-0.3; scripts and clients are the
   interface (`save`/`play`/`stop`/`frame`, renamed from the
   `save_frame`-era verbs).

## Prototype numbers (2026-07-03/04, M2-sizing evidence)

- 250 m sea, 32 frames as units: generation + sync fine (paced bursts —
  unpaced floods drop the client session); mesher thrash kills it.
- 60 m x 32 frames: works, 0.57 GB total, ~2.5 min generation, loops
  seamlessly at 8 fps with dispersion-snapped wave speeds.
- Palette work pays off here: all frames share the unit palette, so a
  320-color animated build bakes its library entries exactly once.
