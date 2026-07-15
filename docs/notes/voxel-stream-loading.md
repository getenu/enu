# Direct-buffer terrain loading (VoxelStream)

Plan for feeding `VoxelTerrain` real voxel buffers **at block-load time** instead
of the current paint-after-load, so paged-in terrain is born with its data —
no empty-then-fill flash and no redundant empty mesh.

## Motivation

Today paging is demand-driven *paint-after-load*:

1. The engine streams a block into view via `VoxelGeneratorFlat` → an **empty**
   block → meshes empty → emits `block_loaded`.
2. `on_block_loaded` (main) requests the chunk's ed data and, when present,
   **paints** it in via `VoxelTool` (`render_snapshot_direct`) / the ASAP
   buffer; late-arriving data is painted by the `packed_chunks` / `chunk_deltas`
   watches.

Consequences: every paged chunk is meshed **twice** (empty, then filled), you
get the visible "chunks pop in as I walk" flash, and content is held redundantly
in the engine buffer, the engine mesh, and the store's decoded cache.

The engine already has the right hook for "return a buffer": a block's initial
buffer is whatever the volume's `VoxelGenerator`/`VoxelStream` produced
(`apply_data_block_response` → `_data_map.set_block_buffer(pos, ob.voxels)` →
`block_loaded`). We just plug in a flat generator and paint over it. The plan is
to supply the *real* buffer at that point.

## Approach (one line)

Attach the chunk's **raw compressed bytes** to the load request on main (Ed-safe,
at request time), and **expand them (decode + resolve) on the streaming thread**
into the block buffer. The block is then born with real content and meshes once.

## The pipeline (thread in brackets)

1. **[main] `VoxelTerrain::send_block_data_requests`** (voxel_terrain.cpp ~772,
   called from `process` ~566): the terrain has decided block X needs loading
   (`_blocks_pending_load`). **This is the Ed-safe hook point.** For each X, read
   the ed replica's chunk X; if resident, `memcpy` its raw packed `SnapshotData`
   bytes into the request; if not resident, leave it empty.
2. **[main] `request_block_load`** (voxel_server.cpp ~399): builds a
   `BlockDataRequest` (TYPE_LOAD), enqueues to the **1-thread** streaming pool
   (`_streaming_thread_pool`, `set_thread_count(1)` ~134).
3. **[streaming] `BlockDataRequest::run`**: creates `voxels`
   (`VoxelBufferInternal` at 16³). **If `enu_chunk` non-empty → expand it**
   (decode RLE/sparse → 4096 `PackedVoxel`; resolve each to an engine type-id;
   bulk-write `voxels`' TYPE channel) and skip the stream. **Else** the existing
   path: `emerge_block` → `RESULT_BLOCK_NOT_FOUND` →
   `request_block_generate_from_data_request` → **general pool** (parallel) fills
   an empty block.
4. **[main] `apply_data_block_response`** (voxel_terrain.cpp ~1064):
   `set_block_buffer(X, ob.voxels)` installs the buffer, schedules the mesh,
   emits `block_loaded`.
5. **[main] `on_block_loaded`** fires *after* the block already has real data.
   Full-clone path: its paint work is unnecessary → shrinks to bookkeeping
   (`loaded_chunks.incl`, frame handling). Fallback path (empty block): it does
   the demand-fetch `request` and the watch fills later (today's behavior).

**Where the chunk is expanded:** step 3, on the streaming thread — that's the CPU
offload. Main only ever hands over the small compressed bytes.

## Key design decisions (settled)

- **Publish RAW, not resolved.** Reuses the compressed ed bytes (no 8 KB
  resolved buffer per chunk → low memory) and moves decode+resolve onto the
  streaming thread (real offload). Trade-off: the resolve needs the palette +
  the process-global **library registry** readable from the streaming thread.
  - Named colors resolve as identity (`library_slot`: `if color_idx <
    STATIC_COLOR_BASE: return color_idx`) — no registry touch. **Only static-RGB
    content** (sea gradients) hits the registry.
  - The **palette** (`Shared.palette`) rides the *same* Build as the chunk, so
    it uses the same thread-safe read path as the chunk bytes — no new surface.
  - The **registry** is the one genuinely new shared structure. It's
    **append-only** (colors get slots, never lose them), so make it
    thread-safe-readable with an `RWLock` (read-mostly) or an atomic snapshot
    pointer. Minor consistency wrinkle: a just-added color could render wrong for
    one frame until re-published — same eventual-consistency class we already
    live with.

- **Don't read Ed cross-thread.** Ed is per-context, tick-driven message-passing
  (`Ed.thread_ctx.tick` every loop iter on main/worker). Locking an ed object in
  place doesn't make it safe — main mutates it during tick without your lock, and
  taxing main to take a lock around *all* ed access is worse. So the raw bytes
  are **copied out of ed on main** into C++-owned memory; the streaming thread
  never touches ed or Nim GC memory.

- **Storage: an owned, variable-length copy on the request.** Add
  `std::vector<uint8_t> enu_chunk;` to `BlockDataRequest` (voxel_server.h ~301),
  next to `voxels`/`instances`. **Not** preallocated (variable RLE length; a
  fixed 8 KB embed wastes memory across in-flight requests). **Not** a ref/ptr
  (source is Nim GC memory, unsafe cross-thread). This matches the struct's own
  documented convention: *"Copy the data for each task — simple information that
  doesn't change after scheduling."* Empty vector = "no data" → fallback. One
  field encodes both paths, no extra flag.

- **Full clones vs partial (the experiment).** Making network contexts **full
  subscribers** means the chunk is always resident at request time → the
  born-with-data path is always taken → the flash/double-mesh disappear
  everywhere. Cost: every client holds the whole level (memory + full sync at
  join). We're trying full clones; want to A/B against partial.

- **Graceful degradation to partial (verified).** If a chunk isn't resident at
  request time (partial subscriber), `enu_chunk` is empty → `run()` falls to
  `emerge_block`→`RESULT_BLOCK_NOT_FOUND`, which **re-dispatches generation to
  the general (parallel) pool** (`request_block_generate_from_data_request` →
  `_general_thread_pool.enqueue`). So the streaming thread only pays a trivial
  "not found"; empty-block generation stays parallel exactly like today. The old
  demand-fetch `request` + fill-on-arrival watch stay in place and carry the
  fallback. **No perf cliff.** Residency picks the path; full-clone simply never
  takes the fallback arm.

## Rejected alternatives (don't revisit)

- **3rd ed context on the streaming thread:** a task-pool thread has no tick
  loop to pump ed; you'd tick inside `emerge_block`, plus carry a full third
  replica. Heavy for one extra thread of parallelism (meshing is already
  parallel on the general pool).
- **Publish resolved buffers:** extra 8 KB/chunk memory and keeps decode+resolve
  on main (no offload).
- **ed pinning / RCU zero-copy read:** real pattern, but overkill to avoid one
  small short-lived copy; keeps complexity out of ed.
- **Maintain a full replica / warm view-region map:** unnecessary — only the
  chunks *in-flight through the streaming pool* need to cross the boundary (a
  handful; batch is up to 16), each copied just-in-time and freed after use.

## Implementation steps

Engine (fork `godot3.x-enu`):

1. `BlockDataRequest`: add `std::vector<uint8_t> enu_chunk;`.
2. **Request-time hook.** The engine doesn't currently give Enu a per-block
   main-side callback before load. Add one so `send_block_data_requests` (or
   `request_block_load`) can ask Enu for block X's bytes and populate
   `enu_chunk`. Shape TBD: a `std::function`/callback on the volume, or a
   virtual the terrain calls. Must run on main.
3. `BlockDataRequest::run`: if `enu_chunk` non-empty, expand into `voxels` (see
   below) and set `has_run`, skipping the stream; else existing not-found path.
4. Make the **library registry** thread-safe-readable (RWLock or atomic
   snapshot) so the expand can resolve static colors off-main.

Nim (`src/`):

5. Implement the request-time hook: read the chunk at world block X from the
   store/ed (`packed_chunks` / `cached_chunk` composes `packed ⊕ deltas ⊕
   pending`, see `voxels/store.nim`), `memcpy` its bytes into `enu_chunk`. Return
   empty when not resident.
6. Implement **expand** (raw bytes → `voxels` TYPE channel): reuse the
   decode+resolve+bulk-fill logic already in `voxels/renderer.nim`
   (`fill_chunk_type_bytes` / `fill_padded_chunk_bytes`) — it does exactly
   decode → `library_slot` resolve → channel write. Factor a variant that fills a
   `VoxelBufferInternal` channel instead of a `PoolByteArray`.
7. Set the terrain to use the stream/hook (replaces the flat-generator-only
   setup in `build_node.nim`; keep the flat generator as the not-found fallback).
8. Make network contexts **full subscribers** (the experiment) — separately
   toggleable so we can A/B vs partial.
9. `on_block_loaded`: the snapshot-paint becomes fallback-only (guard on "did the
   block arrive empty"); keep the demand-fetch `request` + watches for partial.

## Verification

- Sea reload: island interiors render immediately (no purple/empty flash), no
  double-mesh (instrument mesh count per chunk), collision holds
  (drop-on-island test).
- `nim test` + `nim test_world` (frame playback still 0-failed).
- A/B full vs partial subscribers: paging smoothness, memory, join time.
- Confirm partial fallback matches today (walk cold terrain; generation stays on
  the general pool).

## Anchors (code we traced)

- Engine: `voxel_server.cpp` — `request_block_load` ~399, `BlockDataRequest::run`
  (stream → NOT_FOUND → `request_block_generate_from_data_request` →
  `_general_thread_pool`), pools `_streaming_thread_pool.set_thread_count(1)`
  ~134 / `_general_thread_pool` ~141. `voxel_terrain.cpp` —
  `send_block_data_requests` ~772, `apply_data_block_response` ~1064.
  `voxel_server.h` — `BlockDataRequest` ~301 + the data-sharing-strategy comment.
- Nim: `src/nodes/build_node.nim` — `on_block_loaded` (demand signal + paint),
  `packed_chunks`/`chunk_deltas` watches. `src/models/voxels/store.nim` —
  `cached_chunk`/`compose_chunk`. `src/models/voxels/renderer.nim` —
  `fill_chunk_type_bytes`/`fill_padded_chunk_bytes` (reuse for expand).
  `src/nodes/voxel_library_registry.nim` — the registry to make thread-safe.
