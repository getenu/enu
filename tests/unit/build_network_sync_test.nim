## Test Build network sync with packed chunks
## This tests the full flow: voxel changes -> dirty tracking -> flush -> network sync -> receive -> apply

import std/[tables, sets]
import unittest2
import pkg/model_citizen
import core
import types
import models/[colors, builds, packed_chunks, voxel_store]

from std/times import init_duration

const recv_duration = init_duration(milliseconds = 50)

# Initialize state for runtime packed chunks toggle
var state* = GameState()

var test_port = 19632

proc next_port(): string =
  result = "127.0.0.1:" & $test_port
  inc test_port

type
  TestResult = object
    sent: int
    recv: int
    content: int  # Actual voxel data bytes (snapshots + deltas)
    voxels: int
    bytes_per_voxel: float

proc run_voxel_sync_test(
    test_name: string,
    disable_packed: bool,
    setup_voxels: proc(store: VoxelStore, server_ctx: ZenContext)
): TestResult =
  ## Run a voxel sync test with VoxelStore.
  ## setup_voxels should add voxels and call apply_changes() as needed.
  let port = next_port()
  let timeout = init_duration(milliseconds = 1000)
  let mode = if disable_packed: "unpacked" else: "packed"

  var server_ctx = ZenContext.init(id = test_name & "_" & mode & "_server", listen_address = port)
  var store = VoxelStore.init(
    id = test_name & "_" & mode & ".voxels",
    ctx = server_ctx,
    disable_packed = disable_packed
  )

  # Setup voxels
  setup_voxels(store, server_ctx)
  server_ctx.boop

  # Reset counters before client connects
  server_ctx.bytes_sent = 0
  server_ctx.bytes_received = 0

  # Client connects
  var client_ctx = ZenContext.init(
    id = test_name & "_" & mode & "_client",
    min_recv_duration = recv_duration,
    max_recv_duration = timeout,
    blocking_recv = true
  )
  client_ctx.subscribe port, callback = proc() = server_ctx.boop(blocking = false)

  # Sync
  for _ in 0 ..< 30:
    server_ctx.boop(blocking = false)
    client_ctx.boop(blocking = false)

  result.sent = server_ctx.bytes_sent
  result.recv = server_ctx.bytes_received
  result.content = store.content_bytes
  result.voxels = store.block_count
  result.bytes_per_voxel = if result.voxels > 0: result.sent.float / result.voxels.float else: 0

  server_ctx.close
  client_ctx.close

proc run_delta_sync_test(
    test_name: string,
    disable_packed: bool,
    add_voxels_incrementally: proc(store: VoxelStore, server_ctx, client_ctx: ZenContext)
): TestResult =
  ## Run a delta sync test - client connects first, then voxels are added incrementally.
  let port = next_port()
  let timeout = init_duration(milliseconds = 1000)
  let mode = if disable_packed: "unpacked" else: "packed"

  var server_ctx = ZenContext.init(id = test_name & "_" & mode & "_server", listen_address = port)
  var store = VoxelStore.init(
    id = test_name & "_" & mode & ".voxels",
    ctx = server_ctx,
    disable_packed = disable_packed
  )

  server_ctx.boop

  # Client connects FIRST (empty state)
  var client_ctx = ZenContext.init(
    id = test_name & "_" & mode & "_client",
    min_recv_duration = recv_duration,
    max_recv_duration = timeout,
    blocking_recv = true
  )
  client_ctx.subscribe port, callback = proc() = server_ctx.boop(blocking = false)

  # Initial sync (empty)
  for _ in 0 ..< 10:
    server_ctx.boop(blocking = false)
    client_ctx.boop(blocking = false)

  # Reset counters after initial sync
  server_ctx.bytes_sent = 0
  server_ctx.bytes_received = 0

  # Now add voxels incrementally
  add_voxels_incrementally(store, server_ctx, client_ctx)

  # Final sync
  for _ in 0 ..< 50:
    server_ctx.boop(blocking = false)
    client_ctx.boop(blocking = false)

  result.sent = server_ctx.bytes_sent
  result.recv = server_ctx.bytes_received
  result.content = store.content_bytes
  result.voxels = store.block_count
  result.bytes_per_voxel = if result.voxels > 0: result.sent.float / result.voxels.float else: 0

  server_ctx.close
  client_ctx.close

proc run_both_formats(
    name: string,
    runner: proc(disable_packed: bool): TestResult
): tuple[packed, unpacked: TestResult] =
  ## Run a test in both packed and unpacked modes, report comparison.
  state.disable_packed_chunks = false
  result.packed = runner(false)
  let p = result.packed
  echo "[", name, "/Packed] ", p.voxels, " voxels | sent: ", p.sent,
       " recv: ", p.recv, " content: ", p.content,
       " | ", p.bytes_per_voxel, " bytes/voxel (sent)"

  state.disable_packed_chunks = true
  result.unpacked = runner(true)
  let u = result.unpacked
  echo "[", name, "/Unpacked] ", u.voxels, " voxels | sent: ", u.sent,
       " recv: ", u.recv, " content: ", u.content,
       " | ", u.bytes_per_voxel, " bytes/voxel (sent)"

  # Report overhead
  if p.content > 0:
    let overhead = p.sent - p.content
    echo "[", name, "] Packed overhead: ", overhead, " bytes (",
         (overhead.float / p.sent.float * 100).int, "% of sent)"

  if p.sent < u.sent:
    echo "[", name, "] Ratio: ", u.sent.float / p.sent.float, "x (packed wins)"
  else:
    echo "[", name, "] Ratio: ", p.sent.float / u.sent.float, "x (unpacked wins)"

Zen.bootstrap

suite "Build Network Sync":
  test "single chunk syncs over network":
    let port = next_port()
    var
      ctx1 = ZenContext.init(id = "build_ctx1")
      ctx2 = ZenContext.init(
        id = "build_ctx2",
        listen_address = port,
        min_recv_duration = recv_duration,
        blocking_recv = true,
      )

    ctx2.subscribe(ctx1)

    # Create packed_chunks table on ctx1
    var packed1 = ZenTable[Vector3, PackedChunk].init(id = "test_packed_1", ctx = ctx1)

    # Create test voxels and encode
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    voxels[linear_position(0, 0, 0)] = pack_voxel(Blue.ord, Manual.ord)
    voxels[linear_position(1, 1, 1)] = pack_voxel(Red.ord, Manual.ord)
    voxels[linear_position(5, 5, 5)] = pack_voxel(Green.ord, Manual.ord)

    packed1[vec3(0, 0, 0)] = encode_chunk(voxels)

    echo "After encode, packed_chunks count: ", packed1.len
    echo "  Chunk (0,0,0) format: ", packed1[vec3(0, 0, 0)].format_name, " size: ", packed1[vec3(0, 0, 0)].data.len

    ctx1.boop
    ctx2.boop

    # Get the packed_chunks on ctx2
    let packed2 = ZenTable[Vector3, PackedChunk](ctx2["test_packed_1"])
    echo "Received packed_chunks count: ", packed2.len

    check packed2.len == 1
    check vec3(0, 0, 0) in packed2

    # Verify content
    let decoded = decode_chunk(packed2[vec3(0, 0, 0)])
    check decoded[linear_position(0, 0, 0)] == pack_voxel(Blue.ord, Manual.ord)
    check decoded[linear_position(1, 1, 1)] == pack_voxel(Red.ord, Manual.ord)
    check decoded[linear_position(5, 5, 5)] == pack_voxel(Green.ord, Manual.ord)

    ctx2.close

  test "multiple chunks sync over network":
    let port = next_port()
    var
      ctx1 = ZenContext.init(id = "build_ctx3")
      ctx2 = ZenContext.init(
        id = "build_ctx4",
        listen_address = port,
        min_recv_duration = recv_duration,
        blocking_recv = true,
      )

    ctx2.subscribe(ctx1)

    var packed1 = ZenTable[Vector3, PackedChunk].init(id = "test_packed_2", ctx = ctx1)

    # Create 4 chunks with different voxels
    for i, chunk_id in [vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1)]:
      var voxels: array[CHUNK_VOLUME, PackedVoxel]
      voxels[linear_position(i, i, i)] = pack_voxel(i + 1, Manual.ord)
      packed1[chunk_id] = encode_chunk(voxels)

    echo "After encode, packed_chunks count: ", packed1.len

    ctx1.boop
    ctx2.boop

    let packed2 = ZenTable[Vector3, PackedChunk](ctx2["test_packed_2"])
    echo "Received packed_chunks count: ", packed2.len

    check packed2.len == 4
    check vec3(0, 0, 0) in packed2
    check vec3(1, 0, 0) in packed2
    check vec3(0, 1, 0) in packed2
    check vec3(0, 0, 1) in packed2

    ctx2.close

  test "flush encode flow syncs correctly":
    let port = next_port()
    var
      ctx1 = ZenContext.init(id = "build_ctx5")
      ctx2 = ZenContext.init(
        id = "build_ctx6",
        listen_address = port,
        min_recv_duration = recv_duration,
        blocking_recv = true,
      )

    ctx2.subscribe(ctx1)

    # Create packed_chunks (default flags include SyncRemote)
    var packed = ZenTable[Vector3, PackedChunk].init(
      id = "test_build_3.packed_chunks", ctx = ctx1
    )

    # Simulate what flush_packed_chunks does: encode voxel data into packed format
    # This represents the data that would come from chunks
    type VoxelData = Table[Vector3, VoxelInfo]
    var local_voxels: VoxelData
    local_voxels[vec3(3, 4, 5)] = (Manual, action_colors[Blue])
    local_voxels[vec3(10, 11, 12)] = (Manual, action_colors[Red])

    # Encode to packed format
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    for pos, info in local_voxels:
      let linear = linear_position(pos.x.int, pos.y.int, pos.z.int)
      let color_idx = info.color.action_index.ord
      let kind_ord = info.kind.ord
      voxels[linear] = pack_voxel(color_idx, kind_ord)

    packed[vec3(0, 0, 0)] = encode_chunk(voxels)

    echo "After encode:"
    echo "  packed_chunks count: ", packed.len
    echo "  Chunk (0,0,0) format: ", packed[vec3(0, 0, 0)].format_name, " size: ", packed[vec3(0, 0, 0)].data.len

    check packed.len == 1

    ctx1.boop
    ctx2.boop

    # Check sync
    let packed2 = ZenTable[Vector3, PackedChunk](ctx2["test_build_3.packed_chunks"])
    echo "Received packed_chunks count: ", packed2.len

    check packed2.len == 1
    check vec3(0, 0, 0) in packed2

    # Decode and verify the content matches
    let decoded = decode_chunk(packed2[vec3(0, 0, 0)])
    let linear1 = linear_position(3, 4, 5)
    let linear2 = linear_position(10, 11, 12)

    check decoded[linear1] != EMPTY_VOXEL
    check decoded[linear2] != EMPTY_VOXEL

    let (c1, k1) = unpack_voxel(decoded[linear1])
    let (c2, k2) = unpack_voxel(decoded[linear2])
    check c1 == Blue.ord
    check k1 == Manual.ord
    check c2 == Red.ord
    check k2 == Manual.ord

    ctx2.close

  test "two-tier sync: late client receives snapshot + deltas":
    ## This test verifies the two-tier sync system:
    ## - packed_chunks: Full snapshots (for late-connecting clients)
    ## - delta_updates: Incremental changes (for connected clients)
    ##
    ## The test:
    ## 1. Add 10 blocks, flush -> creates snapshot in packed_chunks
    ## 2. Add 1 more block, flush -> creates delta in delta_updates
    ## 3. Late client connects
    ## 4. Client receives snapshot (10 voxels) + delta (1 voxel) = 11 total
    let port = next_port()
    let timeout = init_duration(milliseconds = 500)

    var server_ctx = ZenContext.init(id = "twotier_server", listen_address = port)

    # Simulate Build's data structures
    var chunks = ZenTable[Vector3, Chunk].init(
      id = "twotier_test.chunks", ctx = server_ctx, flags = {SyncLocal}
    )
    var packed_chunks = ZenTable[Vector3, PackedChunk].init(
      id = "twotier_test.packed_chunks", ctx = server_ctx, flags = {SyncLocal, SyncRemote}
    )
    var delta_updates = ZenSeq[DeltaUpdate].init(
      id = "twotier_test.delta_updates", ctx = server_ctx, flags = {SyncLocal, SyncRemote}
    )

    # Track last snapshot for determining deltas
    var last_snapshot: Table[Vector3, HashSet[Vector3]]
    var dirty: HashSet[Vector3]

    proc flush_two_tier() =
      ## Two-tier flush: snapshots go to packed_chunks, deltas go to delta_updates
      for chunk_id in dirty:
        var voxels: array[CHUNK_VOLUME, PackedVoxel]
        var current_positions: HashSet[Vector3]

        if chunk_id in chunks:
          for pos, info in chunks[chunk_id]:
            let lx = int(pos.x) mod 16
            let ly = int(pos.y) mod 16
            let lz = int(pos.z) mod 16
            voxels[linear_position(lx, ly, lz)] = pack_voxel(
              info.color.action_index.ord, info.kind.ord
            )
            current_positions.incl(pos)

        let had_snapshot = chunk_id in last_snapshot
        let last_positions = if had_snapshot: last_snapshot[chunk_id]
                             else: initHashSet[Vector3]()

        if not had_snapshot:
          # First time: create snapshot
          let packed = encode_chunk(voxels)
          packed_chunks[chunk_id] = packed
          last_snapshot[chunk_id] = current_positions
          echo "[TwoTier] Created snapshot for chunk ", chunk_id, " with ", current_positions.len, " voxels"
        else:
          # Subsequent: create delta
          var changes: seq[tuple[pos: Vector3, voxel: PackedVoxel]]
          for pos in current_positions:
            if pos notin last_positions:
              let lx = int(pos.x) mod 16
              let ly = int(pos.y) mod 16
              let lz = int(pos.z) mod 16
              changes.add (vec3(lx.float, ly.float, lz.float), voxels[linear_position(lx, ly, lz)])
          for pos in last_positions:
            if pos notin current_positions:
              let lx = int(pos.x) mod 16
              let ly = int(pos.y) mod 16
              let lz = int(pos.z) mod 16
              changes.add (vec3(lx.float, ly.float, lz.float), EMPTY_VOXEL)

          if changes.len > 0:
            let delta = encode_delta(changes)
            delta_updates.add delta
            last_snapshot[chunk_id] = current_positions
            echo "[TwoTier] Created delta for chunk ", chunk_id, " with ", changes.len, " changes"

      dirty.clear

    # STEP 1: Add 10 blocks -> creates snapshot
    chunks[vec3(0, 0, 0)] = Chunk.init(ctx = server_ctx)
    for i in 0 ..< 10:
      chunks[vec3(0, 0, 0)][vec3(float(i), 0, 0)] = (Manual, action_colors[Blue])
    dirty.incl(vec3(0, 0, 0))
    flush_two_tier()
    server_ctx.boop
    echo "[TwoTier] packed_chunks has ", packed_chunks.len, " entries"
    echo "[TwoTier] delta_updates has ", delta_updates.len, " entries"

    # STEP 2: Add 1 more block -> creates delta (not new snapshot)
    chunks[vec3(0, 0, 0)][vec3(10, 0, 0)] = (Manual, action_colors[Red])
    dirty.incl(vec3(0, 0, 0))
    flush_two_tier()
    server_ctx.boop
    echo "[TwoTier] After second flush:"
    echo "[TwoTier]   packed_chunks has ", packed_chunks.len, " entries"
    echo "[TwoTier]   delta_updates has ", delta_updates.len, " entries"

    # Verify server state
    check packed_chunks.len == 1  # One snapshot
    check delta_updates.len == 1  # One delta

    # STEP 3: Late client connects
    var client_ctx = ZenContext.init(
      id = "twotier_client", min_recv_duration = recv_duration, max_recv_duration = timeout
    )
    client_ctx.subscribe port, callback = proc() = server_ctx.boop(blocking = false)

    for _ in 0 ..< 10:
      server_ctx.boop(blocking = false)
      client_ctx.boop(blocking = false)

    # STEP 4: Verify client received both snapshot and delta
    let has_packed = "twotier_test.packed_chunks" in client_ctx
    let has_deltas = "twotier_test.delta_updates" in client_ctx
    echo "[TwoTier] Client has packed_chunks: ", has_packed
    echo "[TwoTier] Client has delta_updates: ", has_deltas

    check has_packed
    check has_deltas

    if has_packed and has_deltas:
      let client_packed = ZenTable[Vector3, PackedChunk](client_ctx["twotier_test.packed_chunks"])
      let client_deltas = ZenSeq[DeltaUpdate](client_ctx["twotier_test.delta_updates"])

      echo "[TwoTier] Client packed_chunks count: ", client_packed.len
      echo "[TwoTier] Client delta_updates count: ", client_deltas.len

      # Count voxels from snapshot
      var snapshot_count = 0
      if vec3(0, 0, 0) in client_packed:
        let decoded = decode_chunk(client_packed[vec3(0, 0, 0)])
        for v in decoded:
          if v != EMPTY_VOXEL:
            inc snapshot_count
      echo "[TwoTier] Voxels from snapshot: ", snapshot_count

      # Count voxels from deltas
      var delta_count = 0
      for delta in client_deltas:
        let changes = decode_delta(delta)
        for (pos, voxel) in changes:
          if voxel != EMPTY_VOXEL:
            inc delta_count
      echo "[TwoTier] Voxels from deltas: ", delta_count

      # Total should be 11 (10 from snapshot + 1 from delta)
      check snapshot_count == 10
      check delta_count == 1
      echo "[TwoTier] Total voxels available to client: ", snapshot_count + delta_count

    server_ctx.close
    client_ctx.close

  test "late-connecting client with actual Build type":
    ## Test using Enu's actual Build type to see if the issue is in Build's
    ## integration rather than raw ZenTable sync.
    ##
    ## NOTE: This test is limited because Build requires full game state.
    ## It tests the packed_chunks sync pattern that Build uses.
    let port = next_port()
    let timeout = init_duration(milliseconds = 500)

    # Mimic Enu's setup: main_ctx on game thread, worker_ctx with listen_address
    var main_ctx = ZenContext.init(id = "build_main")
    var worker_ctx = ZenContext.init(
      id = "build_worker",
      listen_address = port,
    )

    # Worker subscribes to main (like in Enu)
    worker_ctx.subscribe(main_ctx)

    # Create Build's tables on main_ctx (like Build.init does)
    # chunks has SyncLocal only
    var chunks = ZenTable[Vector3, Chunk].init(
      id = "build_test.chunks",
      ctx = main_ctx,
      flags = {SyncLocal}
    )
    # packed_chunks has SyncLocal + SyncRemote
    var packed_chunks = ZenTable[Vector3, PackedChunk].init(
      id = "build_test.packed_chunks",
      ctx = main_ctx,
      flags = {SyncLocal, SyncRemote}
    )

    var dirty: HashSet[Vector3]

    proc add_voxel(pos: Vector3, info: VoxelInfo) =
      let buffer = (pos / vec3(16, 16, 16)).floor
      if buffer notin chunks:
        chunks[buffer] = Chunk.init(ctx = main_ctx)
      chunks[buffer][pos] = info
      dirty.incl(buffer)

    proc flush() =
      for chunk_id in dirty:
        var voxels: array[CHUNK_VOLUME, PackedVoxel]
        if chunk_id in chunks:
          for pos, info in chunks[chunk_id]:
            let lx = int(pos.x - chunk_id.x * 16) mod 16
            let ly = int(pos.y - chunk_id.y * 16) mod 16
            let lz = int(pos.z - chunk_id.z * 16) mod 16
            voxels[linear_position(lx, ly, lz)] = pack_voxel(
              info.color.action_index.ord, info.kind.ord
            )
        let packed = encode_chunk(voxels)
        if not packed.is_empty:
          packed_chunks[chunk_id] = packed
      dirty.clear

    # Build some blocks over multiple frames (like speed=1 building)
    add_voxel(vec3(0, 0, 0), (Manual, action_colors[Blue]))
    flush()
    main_ctx.boop
    worker_ctx.boop
    echo "[Build] Frame 1"

    add_voxel(vec3(5, 5, 5), (Manual, action_colors[Red]))
    flush()
    main_ctx.boop
    worker_ctx.boop
    echo "[Build] Frame 2"

    add_voxel(vec3(20, 0, 0), (Manual, action_colors[Green]))  # Different chunk
    flush()
    main_ctx.boop
    worker_ctx.boop
    echo "[Build] Frame 3"

    echo "[Build] packed_chunks on main: ", packed_chunks.len
    echo "[Build] packed_chunks on worker: ", ZenTable[Vector3, PackedChunk](worker_ctx["build_test.packed_chunks"]).len

    # NOW late client connects to worker (like Enu client joining)
    var client_ctx = ZenContext.init(
      id = "build_client",
      min_recv_duration = recv_duration,
      max_recv_duration = timeout,
    )

    client_ctx.subscribe port,
      callback = proc() =
        worker_ctx.boop(blocking = false)

    echo "[Build] Client connected"

    # Sync
    for _ in 0 ..< 10:
      main_ctx.boop(blocking = false)
      worker_ctx.boop(blocking = false)
      client_ctx.boop(blocking = false)

    # Check what client sees
    let has_packed = "build_test.packed_chunks" in client_ctx
    echo "[Build] Client has packed_chunks: ", has_packed

    if has_packed:
      let client_packed = ZenTable[Vector3, PackedChunk](client_ctx["build_test.packed_chunks"])
      echo "[Build] Client received ", client_packed.len, " packed chunks"
      check client_packed.len == 2  # Two chunks: (0,0,0) and (1,0,0)
    else:
      echo "[Build] FAIL: no packed_chunks"
      check false

    worker_ctx.close
    client_ctx.close

  test "late-connecting client misses older packed_chunks (EXPECTED TO FAIL)":
    ## This test attempts to reproduce the actual bug in Enu:
    ## When a client connects late, they don't receive blocks that were
    ## created before their connection.
    ##
    ## The hypothesis is that packed_chunks doesn't properly sync existing
    ## data when a new subscriber joins.
    ##
    ## If this test PASSES, it means model_citizen's ZenTable sync works
    ## correctly and the bug is elsewhere in Enu's integration.
    let port = next_port()
    let timeout = init_duration(milliseconds = 500)

    # Server context with listen_address
    var server_ctx = ZenContext.init(
      id = "fail_server",
      listen_address = port,
    )

    # Create packed_chunks and chunks like Build does
    # packed_chunks syncs to remote, chunks is local only
    var chunks_server = ZenTable[Vector3, ZenTable[Vector3, VoxelInfo]].init(
      id = "fail_test.chunks",
      ctx = server_ctx,
      flags = {SyncLocal}  # Local only, like in Build
    )
    var packed_server = ZenTable[Vector3, PackedChunk].init(
      id = "fail_test.packed_chunks",
      ctx = server_ctx,
      flags = {SyncLocal, SyncRemote}  # Network sync, like in Build
    )
    var dirty_chunks: HashSet[Vector3]

    # Helper to flush like Build.flush_packed_chunks
    proc flush() =
      for chunk_id in dirty_chunks:
        var voxels: array[CHUNK_VOLUME, PackedVoxel]
        if chunk_id in chunks_server:
          for pos, info in chunks_server[chunk_id]:
            let local_x = int(pos.x) mod 16
            let local_y = int(pos.y) mod 16
            let local_z = int(pos.z) mod 16
            let linear = linear_position(local_x, local_y, local_z)
            let color_idx = info.color.action_index.ord
            voxels[linear] = pack_voxel(color_idx, info.kind.ord)
        let packed = encode_chunk(voxels)
        if not packed.is_empty:
          packed_server[chunk_id] = packed
      dirty_chunks.clear

    # Simulate building blocks over multiple frames
    # FRAME 1
    chunks_server[vec3(0, 0, 0)] = ZenTable[Vector3, VoxelInfo].init(ctx = server_ctx)
    chunks_server[vec3(0, 0, 0)][vec3(0, 0, 0)] = (Manual, action_colors[Blue])
    dirty_chunks.incl(vec3(0, 0, 0))
    flush()
    server_ctx.boop
    echo "[Fail] Frame 1: chunk (0,0,0)"

    # FRAME 2
    chunks_server[vec3(1, 0, 0)] = ZenTable[Vector3, VoxelInfo].init(ctx = server_ctx)
    chunks_server[vec3(1, 0, 0)][vec3(16, 0, 0)] = (Manual, action_colors[Red])
    dirty_chunks.incl(vec3(1, 0, 0))
    flush()
    server_ctx.boop
    echo "[Fail] Frame 2: chunk (1,0,0)"

    # FRAME 3
    chunks_server[vec3(0, 1, 0)] = ZenTable[Vector3, VoxelInfo].init(ctx = server_ctx)
    chunks_server[vec3(0, 1, 0)][vec3(0, 16, 0)] = (Manual, action_colors[Green])
    dirty_chunks.incl(vec3(0, 1, 0))
    flush()
    server_ctx.boop
    echo "[Fail] Frame 3: chunk (0,1,0)"

    echo "[Fail] Server packed_chunks has ", packed_server.len, " entries"

    # Late-connecting client
    var client_ctx = ZenContext.init(
      id = "fail_client",
      min_recv_duration = recv_duration,
      max_recv_duration = timeout,
    )

    # Subscribe with callback to tick server
    client_ctx.subscribe port,
      callback = proc() =
        server_ctx.boop(blocking = false)

    # Create client's chunks table and set up watch (like Build.main_thread_joined)
    var chunks_client = ZenTable[Vector3, ZenTable[Vector3, VoxelInfo]].init(
      id = "fail_test.chunks",
      ctx = client_ctx,
      flags = {SyncLocal}
    )

    # Sync
    for _ in 0 ..< 10:
      server_ctx.boop(blocking = false)
      client_ctx.boop(blocking = false)

    # Check packed_chunks on client
    let has_packed = "fail_test.packed_chunks" in client_ctx
    echo "[Fail] Client has packed_chunks: ", has_packed

    if has_packed:
      let packed_client = ZenTable[Vector3, PackedChunk](client_ctx["fail_test.packed_chunks"])
      echo "[Fail] Client packed_chunks has ", packed_client.len, " entries"

      # This check documents whether late-connect works
      # If this fails, packed_chunks design is broken for late-connect
      check packed_client.len == 3
    else:
      echo "[Fail] Client doesn't have packed_chunks table at all"
      check false

    server_ctx.close
    client_ctx.close

  test "late-connecting client with incremental packed_chunks updates":
    ## This test simulates the REAL Enu scenario:
    ## - Host builds blocks incrementally over multiple frames
    ## - Each frame, dirty chunks are flushed to packed_chunks
    ## - After several frames, a client connects
    ## - Client should see ALL blocks, not just the last delta
    ##
    ## THIS TEST SHOULD FAIL with packed_chunks design because late clients
    ## only receive recent changes, not the full accumulated state.
    let port = next_port()
    let timeout = init_duration(milliseconds = 500)

    # Create server context
    var server_ctx = ZenContext.init(
      id = "incr_server",
      listen_address = port,
    )

    # Simulate packed_chunks like Build uses it
    var packed_server = ZenTable[Vector3, PackedChunk].init(
      id = "incr_test.packed_chunks",
      ctx = server_ctx,
      flags = {SyncLocal, SyncRemote}
    )

    # FRAME 1: Build some blocks in chunk (0,0,0)
    block:
      var voxels: array[CHUNK_VOLUME, PackedVoxel]
      voxels[linear_position(0, 0, 0)] = pack_voxel(Blue.ord, Manual.ord)
      voxels[linear_position(1, 1, 1)] = pack_voxel(Blue.ord, Manual.ord)
      packed_server[vec3(0, 0, 0)] = encode_chunk(voxels)
    server_ctx.boop
    echo "[Incr] Frame 1: Added chunk (0,0,0) with 2 voxels"

    # FRAME 2: Build some blocks in chunk (1,0,0)
    block:
      var voxels: array[CHUNK_VOLUME, PackedVoxel]
      voxels[linear_position(5, 5, 5)] = pack_voxel(Red.ord, Manual.ord)
      packed_server[vec3(1, 0, 0)] = encode_chunk(voxels)
    server_ctx.boop
    echo "[Incr] Frame 2: Added chunk (1,0,0) with 1 voxel"

    # FRAME 3: Build some blocks in chunk (0,1,0)
    block:
      var voxels: array[CHUNK_VOLUME, PackedVoxel]
      voxels[linear_position(3, 3, 3)] = pack_voxel(Green.ord, Manual.ord)
      packed_server[vec3(0, 1, 0)] = encode_chunk(voxels)
    server_ctx.boop
    echo "[Incr] Frame 3: Added chunk (0,1,0) with 1 voxel"

    echo "[Incr] Server has ", packed_server.len, " packed chunks before client connects"
    check packed_server.len == 3

    # NOW client connects (late connection)
    var client_ctx = ZenContext.init(
      id = "incr_client",
      min_recv_duration = recv_duration,
      max_recv_duration = timeout,
      blocking_recv = true,
    )

    client_ctx.subscribe port,
      callback = proc() =
        server_ctx.boop(blocking = false)

    echo "[Incr] Client connected"

    # Sync
    for _ in 0 ..< 5:
      server_ctx.boop(blocking = false)
      client_ctx.boop(blocking = false)

    # Check what client received
    let has_table = "incr_test.packed_chunks" in client_ctx
    echo "[Incr] Client has table: ", has_table

    if has_table:
      let packed_client = ZenTable[Vector3, PackedChunk](client_ctx["incr_test.packed_chunks"])
      echo "[Incr] Client received ", packed_client.len, " packed chunks"

      # Client SHOULD have all 3 chunks - this is the test that may fail
      check packed_client.len == 3
      check vec3(0, 0, 0) in packed_client
      check vec3(1, 0, 0) in packed_client
      check vec3(0, 1, 0) in packed_client

      if vec3(0, 0, 0) in packed_client:
        let decoded = decode_chunk(packed_client[vec3(0, 0, 0)])
        let v1 = decoded[linear_position(0, 0, 0)]
        let v2 = decoded[linear_position(1, 1, 1)]
        echo "[Incr] Chunk (0,0,0) voxels: ", v1, ", ", v2
        check v1 == pack_voxel(Blue.ord, Manual.ord)
        check v2 == pack_voxel(Blue.ord, Manual.ord)
    else:
      echo "[Incr] FAIL: Table not received"
      check false

    server_ctx.close
    client_ctx.close

  test "late-connecting client with direct chunks (no packing)":
    ## This test shows that syncing chunks directly (without packing) works
    ## for late-connecting clients. This is what -d:disablePackedChunks enables.
    let port = next_port()
    let timeout = init_duration(milliseconds = 500)

    # Create server context
    var server_ctx = ZenContext.init(
      id = "direct_server",
      listen_address = port,
    )

    # Simulate direct chunks sync (like with -d:disablePackedChunks)
    var chunks_server = ZenTable[Vector3, ZenTable[Vector3, VoxelInfo]].init(
      id = "direct_test.chunks",
      ctx = server_ctx,
      flags = {SyncLocal, SyncRemote}
    )

    # FRAME 1: Build some blocks in chunk (0,0,0)
    chunks_server[vec3(0, 0, 0)] = ZenTable[Vector3, VoxelInfo].init(ctx = server_ctx)
    chunks_server[vec3(0, 0, 0)][vec3(0, 0, 0)] = (Manual, action_colors[Blue])
    chunks_server[vec3(0, 0, 0)][vec3(1, 1, 1)] = (Manual, action_colors[Blue])
    server_ctx.boop
    echo "[Direct] Frame 1: Added chunk (0,0,0) with 2 voxels"

    # FRAME 2: Build some blocks in chunk (1,0,0)
    chunks_server[vec3(1, 0, 0)] = ZenTable[Vector3, VoxelInfo].init(ctx = server_ctx)
    chunks_server[vec3(1, 0, 0)][vec3(21, 5, 5)] = (Manual, action_colors[Red])
    server_ctx.boop
    echo "[Direct] Frame 2: Added chunk (1,0,0) with 1 voxel"

    # FRAME 3: Build some blocks in chunk (0,1,0)
    chunks_server[vec3(0, 1, 0)] = ZenTable[Vector3, VoxelInfo].init(ctx = server_ctx)
    chunks_server[vec3(0, 1, 0)][vec3(3, 19, 3)] = (Manual, action_colors[Green])
    server_ctx.boop
    echo "[Direct] Frame 3: Added chunk (0,1,0) with 1 voxel"

    echo "[Direct] Server has ", chunks_server.len, " chunks before client connects"
    check chunks_server.len == 3

    # NOW client connects (late connection)
    var client_ctx = ZenContext.init(
      id = "direct_client",
      min_recv_duration = recv_duration,
      max_recv_duration = timeout,
      blocking_recv = true,
    )

    client_ctx.subscribe port,
      callback = proc() =
        server_ctx.boop(blocking = false)

    echo "[Direct] Client connected"

    # Sync
    for _ in 0 ..< 5:
      server_ctx.boop(blocking = false)
      client_ctx.boop(blocking = false)

    # Check what client received
    let has_table = "direct_test.chunks" in client_ctx
    echo "[Direct] Client has table: ", has_table

    if has_table:
      let chunks_client = ZenTable[Vector3, ZenTable[Vector3, VoxelInfo]](
        client_ctx["direct_test.chunks"]
      )
      echo "[Direct] Client received ", chunks_client.len, " chunks"

      # Client SHOULD have all 3 chunks - this should pass
      check chunks_client.len == 3
      check vec3(0, 0, 0) in chunks_client
      check vec3(1, 0, 0) in chunks_client
      check vec3(0, 1, 0) in chunks_client

      if vec3(0, 0, 0) in chunks_client:
        echo "[Direct] Chunk (0,0,0) has ", chunks_client[vec3(0, 0, 0)].len, " voxels"
        check chunks_client[vec3(0, 0, 0)].len == 2
    else:
      echo "[Direct] FAIL: Table not received"
      check false

    server_ctx.close
    client_ctx.close

  test "late-connecting client receives existing packed chunks (network)":
    ## This tests network subscription - client connects AFTER blocks already exist.
    ## Server has data BEFORE client connects over network.
    ## This is the scenario Enu uses: server (host) creates world, client joins later.
    let server_port = "127.0.0.1:9634"
    let timeout = init_duration(milliseconds = 500)

    # Create data provider context (no listen_address)
    var data_ctx = ZenContext.init(id = "net_data_ctx")

    # Create listener context with listen_address and timeout
    var listener_ctx = ZenContext.init(
      id = "net_listener_ctx",
      listen_address = server_port,
      min_recv_duration = recv_duration,
      max_recv_duration = timeout,
      blocking_recv = true,
    )

    # Listener subscribes locally to data_ctx
    listener_ctx.subscribe(data_ctx)

    # Create packed_chunks on data_ctx and populate BEFORE client connects
    var packed_data = ZenTable[Vector3, PackedChunk].init(
      id = "net_late_test.packed_chunks", ctx = data_ctx
    )

    # Add multiple chunks with voxels
    for i, chunk_id in [vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0)]:
      var voxels: array[CHUNK_VOLUME, PackedVoxel]
      voxels[linear_position(i, i, i)] = pack_voxel(Blue.ord, Manual.ord)
      voxels[linear_position(i+1, i+1, i+1)] = pack_voxel(Red.ord, Manual.ord)
      packed_data[chunk_id] = encode_chunk(voxels)

    echo "[Net] Server has ", packed_data.len, " packed chunks before client connects"

    # Commit changes before client connects
    data_ctx.boop
    listener_ctx.boop

    # NOW create client context and connect over network (late connection)
    var client_ctx = ZenContext.init(
      id = "net_client_ctx",
      min_recv_duration = recv_duration,
      max_recv_duration = timeout,
      blocking_recv = true,
    )

    # Client subscribes to listener over network with callback to tick server
    client_ctx.subscribe server_port,
      callback = proc() =
        listener_ctx.boop(blocking = false)

    echo "[Net] Client subscribed to server at ", server_port

    # Sync - use non-blocking boops to avoid deadlock
    for _ in 0 ..< 5:
      data_ctx.boop(blocking = false)
      listener_ctx.boop(blocking = false)
      client_ctx.boop(blocking = false)

    echo "[Net] After boops"

    # Check if we can see the table
    let has_table = "net_late_test.packed_chunks" in client_ctx
    echo "[Net] client_ctx has table: ", has_table

    if has_table:
      let packed_client = ZenTable[Vector3, PackedChunk](client_ctx["net_late_test.packed_chunks"])
      echo "[Net] Client received ", packed_client.len, " packed chunks after late connect"

      # This test documents the current behavior - late-connecting clients
      # may not receive all existing data
      check packed_client.len == 3
      check vec3(0, 0, 0) in packed_client
      check vec3(1, 0, 0) in packed_client
      check vec3(0, 1, 0) in packed_client
    else:
      echo "[Net] BUG: Table not received after late connect"
      check false

    listener_ctx.close
    client_ctx.close

  test "large chunk with many voxels syncs correctly":
    let port = next_port()
    var
      ctx1 = ZenContext.init(id = "build_ctx7")
      ctx2 = ZenContext.init(
        id = "build_ctx8",
        listen_address = port,
        min_recv_duration = recv_duration,
        blocking_recv = true,
      )

    ctx2.subscribe(ctx1)

    var packed1 = ZenTable[Vector3, PackedChunk].init(id = "test_packed_large", ctx = ctx1)

    # Fill a chunk with voxels (simulating a solid cube)
    var voxels: array[CHUNK_VOLUME, PackedVoxel]
    var count = 0
    for x in 0 ..< 8:
      for y in 0 ..< 8:
        for z in 0 ..< 8:
          voxels[linear_position(x, y, z)] = pack_voxel(Blue.ord, Manual.ord)
          inc count

    echo "Created ", count, " voxels"

    packed1[vec3(0, 0, 0)] = encode_chunk(voxels)
    echo "Encoded size: ", packed1[vec3(0, 0, 0)].data.len, " bytes"
    echo "Format: ", packed1[vec3(0, 0, 0)].format_name

    ctx1.boop
    ctx2.boop

    let packed2 = ZenTable[Vector3, PackedChunk](ctx2["test_packed_large"])
    check packed2.len == 1

    let decoded = decode_chunk(packed2[vec3(0, 0, 0)])

    # Verify all voxels
    var decoded_count = 0
    for x in 0 ..< 8:
      for y in 0 ..< 8:
        for z in 0 ..< 8:
          check decoded[linear_position(x, y, z)] == pack_voxel(Blue.ord, Manual.ord)
          inc decoded_count

    echo "Verified ", decoded_count, " voxels"

    ctx2.close

  test "mixed density - packed vs unpacked":
    ## 1200 blocks across 16 chunks with varying colors.
    let (packed, unpacked) = run_both_formats("mixed", proc(disable_packed: bool): TestResult =
      run_voxel_sync_test("mixed", disable_packed, proc(store: VoxelStore, ctx: ZenContext) =
        for cx in 0 ..< 4:
          for cy in 0 ..< 4:
            for x in 0 ..< 5:
              for y in 0 ..< 5:
                for z in 0 ..< 3:
                  let color_idx = (cx + cy + x + y + z) mod 7
                  let pos = vec3((cx * 16 + x).float, (cy * 16 + y).float, z.float)
                  store.add_voxel(pos, (Manual, action_colors[Colors(color_idx)]), disable_packed)
        store.apply_changes(disable_packed)
      )
    )
    check packed.sent < unpacked.sent

  test "dense non-repeating - packed vs unpacked":
    ## Full 16x16x16 chunks with varying colors (worst case for RLE).
    let (packed, unpacked) = run_both_formats("dense", proc(disable_packed: bool): TestResult =
      run_voxel_sync_test("dense", disable_packed, proc(store: VoxelStore, ctx: ZenContext) =
        for cx in 0 ..< 2:
          for cy in 0 ..< 2:
            for x in 0 ..< 16:
              for y in 0 ..< 16:
                for z in 0 ..< 16:
                  let color_idx = (x + y * 2 + z * 3) mod 7
                  let pos = vec3((cx * 16 + x).float, (cy * 16 + y).float, z.float)
                  store.add_voxel(pos, (Manual, action_colors[Colors(color_idx)]), disable_packed)
        store.apply_changes(disable_packed)
      )
    )
    check packed.sent < unpacked.sent

  test "sparse - packed vs unpacked":
    ## Only 4 voxels per chunk across 16 chunks (64 total voxels).
    let (packed, unpacked) = run_both_formats("sparse", proc(disable_packed: bool): TestResult =
      run_voxel_sync_test("sparse", disable_packed, proc(store: VoxelStore, ctx: ZenContext) =
        for cx in 0 ..< 4:
          for cy in 0 ..< 4:
            store.add_voxel(vec3((cx * 16).float, (cy * 16).float, 0),
                           (Manual, action_colors[Colors(0)]), disable_packed)
            store.add_voxel(vec3((cx * 16 + 15).float, (cy * 16).float, 0),
                           (Manual, action_colors[Colors(1)]), disable_packed)
            store.add_voxel(vec3((cx * 16).float, (cy * 16 + 15).float, 0),
                           (Manual, action_colors[Colors(2)]), disable_packed)
            store.add_voxel(vec3((cx * 16 + 15).float, (cy * 16 + 15).float, 15),
                           (Manual, action_colors[Colors(3)]), disable_packed)
        store.apply_changes(disable_packed)
      )
    )
    check packed.sent < unpacked.sent

  test "delta updates - packed vs unpacked":
    ## Client connects first, then voxels added incrementally.
    ## Tests true delta encoding efficiency.
    let (packed, unpacked) = run_both_formats("delta", proc(disable_packed: bool): TestResult =
      run_delta_sync_test("delta", disable_packed,
        proc(store: VoxelStore, server_ctx, client_ctx: ZenContext) =
          for batch in 0 ..< 10:
            for i in 0 ..< 10:
              let idx = batch * 10 + i
              let chunk_x = idx div 25
              let chunk_y = (idx mod 25) div 5
              let local_x = idx mod 5
              let local_y = (idx div 5) mod 5
              let pos = vec3((chunk_x * 16 + local_x).float, (chunk_y * 16 + local_y).float, 0)
              store.add_voxel(pos, (Manual, action_colors[Colors(idx mod 7)]), disable_packed)
            store.apply_changes(disable_packed)
            for _ in 0 ..< 20:
              server_ctx.boop(blocking = false)
              client_ctx.boop(blocking = false)
      )
    )
    # Delta may or may not be smaller - just report, don't assert
    discard (packed, unpacked)
