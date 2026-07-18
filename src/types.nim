import std/[tables, monotimes, times, sets, options, macros]

type
  # A general way to run a query against a thing from another context (another
  # thread, or a remote process over the network). The asker fills in a
  # ThingQuery and sets the thing's `query` to it with state PENDING; the
  # context that owns the thing's behavior answers by writing the same value
  # back with `result`/`error` filled in and state DONE. Today only
  # EPHEMERAL bots subscribe for answers (see bots.nim and bot_node.nim), but the
  # slot exists on every thing.
  ThingQueryKind* = enum
    BLANK
    SCREENSHOT
    EVAL
    CONSOLE
    CLEAR_CONSOLE
    LEVEL_DIR
    PING

  ThingQueryState* = enum
    IDLE
    PENDING
    READY
    DONE

  ThingQuery* = object
    kind*: ThingQueryKind
    code*: string
    result*: string
    error*: string
    state*: ThingQueryState
    top_level*: bool
    thing_id*: string
    screenshot_from_player*: bool
    screenshot_with_ui*: bool
    screenshot_top_down*: bool
    screenshot_size*: float

import godotapi/[spatial, ray_cast]
import pkg/core/godotcoretypes except Color
import pkg/core/[vector3, basis, aabb, godotbase]
import pkg/compiler/[ast, lineinfos, semdata]
import ed
import models/colors, libs/[eval]

from pkg/godot import NimGodotObject

export Vector3, Transform, Basis, vector3, basis, AABB, aabb
export godotbase except print
export Interpreter
export lineinfos.`==`

const
  ChunkDim* = 16
  CHUNK_VOLUME* = ChunkDim * ChunkDim * ChunkDim # 4096
  ChunkSize* = vec3(16, 16, 16)
  MAX_BUILD_DIMENSION* = 65535 # VoxelBuffer.MAX_SIZE
  EMPTY_VOXEL* = 0'u16

  # Voxel color index ranges. 0..6 are the named `Colors`; 7..63 are reserved
  # for named-palette growth; STATIC_COLOR_BASE+ are per-Shared static RGB
  # palette entries (env-independent).
  STATIC_COLOR_BASE* = 64
  MAX_STATIC_COLORS* = 4096
  MAX_FRAMES* = 64
    ## Animation frame cap per build: frames persist across script re-runs
    ## (clearing is explicit via clear_frames), so an unguarded save
    ## in a loop would grow forever. Call 65 raises.

  # Delta thresholds
  MAX_CHANGES_FOR_DELTA* = 100
  MAX_DELTAS_BEFORE_SNAPSHOT* = 100

  MAIN_CHUNK_CACHE_CAP* = 256
    ## Max decoded chunks resident on the main thread (~2 MB at u16 cells).
    ## Main only runs interactive point queries, so a bounded LRU suffices;
    ## the worker is unbounded (see VoxelStore.cache_cap). Eviction is an
    ## O(cap) scan per miss-at-cap (see cached_chunk) — fine at this size,
    ## but rethink it (a real LRU list, or sampled eviction) before growing
    ## past ~512.

type
  PackedVoxel* = uint16

  SnapshotData* = object
    data*: string

  DeltaUpdate* = object
    data*: string

  PackedChunk* = SnapshotData # Legacy alias

  VoxelKind* = enum
    ## Ordinals are persisted (JSON edits) and on the wire — keep positions.
    HOLE
    PERSISTED ## hand-style edits; saved with the unit and restored on load
    TRANSIENT ## dropped on script restart — the script regenerates them

  VoxelInfo* = tuple[kind: VoxelKind, color: Color]

  Pen* = tuple[position: Transform, color: Color, drawing: bool]
    ## A build's drawing context — turtle pose, color, pen-down state.
    ## Scripts capture and restore it through the `pen` accessor. A plain
    ## tuple for now; it will grow into an object.

  FrameData* = object
    ## One animation frame: the unit's whole voxel state as packed chunks —
    ## the same encoding the sync layer uses. Frames are data; meshes are
    ## derived per side (see docs/notes/voxel-frame-animation.md).
    chunks*: Table[Vector3, SnapshotData]

  EditKey* = tuple[id: string, loc: Vector3]

type
  EnuError* = object of CatchableError
  ResourceLimitError* = object of CatchableError
  LocalStateFlags* = enum
    COMMAND_MODE
    EDITOR_VISIBLE
    CONSOLE_VISIBLE
    BLOCK_TARGET_VISIBLE
    RETICLE_VISIBLE
    DOCS_VISIBLE
    SETTINGS_VISIBLE
    MOUSE_CAPTURED
    PRIMARY_DOWN
    SECONDARY_DOWN
    EDITOR_FOCUSED
    CONSOLE_FOCUSED
    DOCS_FOCUSED
    SETTINGS_FOCUSED
    VIEWPORT_FOCUSED
    PLAYING
    FLYING
    GOD
    ALT_WALK_SPEED
    ALT_FLY_SPEED
    LOADING_SCRIPT
    SERVER
    QUITTING
    RESETTING_VM
    NEEDS_RESTART
    CONNECTING
    SCENE_READY
    TOUCH_CONTROLS
    FULL_WIDTH_PANELS
    EDITOR_OPENING
    EDITOR_CLOSING
    TEST_MODE
    FLY_DISABLED
    SPAWN_HELD
      ## LOCAL (never synced): this main thread is holding its player at the
      ## spawn — frozen (no gravity/movement/look) with the splash up — until
      ## its own copy of the units ahead of the PLAYERS step has rendered. Each
      ## client releases independently; the server can't know a remote client's
      ## render state. game.process computes it from the synced LOAD_SCREEN
      ## signal plus the local render readiness of the gate units.

  GlobalStateFlags* = enum
    LOADING_LEVEL
    SPAWNING
      ## Unused; superseded by the local SPAWN_HELD spawn gate. Kept because
      ## these ordinals are on the wire — append, never reorder/remove.
    LOAD_SCREEN
      ## Server-authored "splash phase" signal: an opaque splash covers the
      ## viewport while the units ahead of the PLAYERS load_order step load.
      ## Set at load start when there are pre-PLAYERS units, cleared at the
      ## PLAYERS step — meaning "splash phase over; reveal once your local
      ## copy of those units has rendered." Each main thread turns it into
      ## its own local SPAWN_HELD (see game.process).

  LocalModelFlags* = enum
    HOVER
    TARGET_MOVED
    HIGHLIGHT
    HIDE

  GlobalModelFlags* = enum
    GLOBAL
    VISIBLE
    LOCK
    READY
    SCRIPT_INITIALIZING
    SCRIPT_LOADING
    SCRIPT_RUNNING
    DIRTY
    RESETTING
    HIGHLIGHT_ERROR
    ASAP_MODE
    EPHEMERAL
      ## Set on things owned by a remote client context — the human's
      ## Player and any client-owned bot (MCP, scripted agents). Agent
      ## things survive level reloads (peer to the human), are skipped
      ## by level persistence (their lifecycle is the client's, not
      ## the level's), and get cleaned up when their owning context
      ## unsubscribes — matched on the thing's `owner_ctx` (the ctx that
      ## created it), which worker.nim reaps on unsubscribe.
    VOXEL_VIEWER
      ## The thing streams voxel terrain around itself: the server attaches
      ## a VoxelViewer node so chunks near the thing get meshed even when no
      ## player is nearby. Off by default — players bring their own viewer,
      ## and most things don't need one. Set it on agent bots that take
      ## screenshots away from the player.
    TRANSFERRING
      ## Transient: the thing is being moved between things collections (see
      ## `adopt`/`release`). Set across the collection remove/add so the
      ## destroy-on-remove watchers (node controller + worker) detach/re-attach
      ## the node instead of tearing the thing down. Synced (SYNC_REMOTE, via
      ## GlobalModelFlags) because every context applies the membership move and
      ## runs the same ungated destroy. Interim until destructor-driven teardown
      ## (getenu/enu#65) makes remove==detach; then this flag goes away.

  Tools* = enum
    CODE_MODE
    BLUE_BLOCK
    RED_BLOCK
    GREEN_BLOCK
    BLACK_BLOCK
    WHITE_BLOCK
    BROWN_BLOCK
    PLACE_BOT
    NONE
    DISABLED

  TaskStates* = enum
    RUNNING
    DONE
    NEXT_TASK

  ConsoleModel* = ref object
    log*: EdSeq[string]

  GameState* = ref object
    local_flags*: EdSet[LocalStateFlags]
    wants*: EdSeq[LocalStateFlags]
    global_flags*: EdSet[GlobalStateFlags]
    config_value*: EdValue[Config]
    open_thing_value*: EdValue[Thing]
    tool_value*: EdValue[Tools]
    tools*: EdSet[Tools]
    gravity*: float
    nodes*: tuple[game: Node, data: Node, player: Node]
    screenshot_camera*: Node
    screenshot_viewport*: Node
    player_camera*: Node
    screenshot_counter*: int
    player_value*: EdValue[Player]
    things*: EdSeq[Thing]
    ground*: Ground
    draw_thing_id*: string
    console*: ConsoleModel
    paused*: bool
    show_prototypes*: bool
    show_tools*: bool # level.json: false starts with no tools (script adds them)
    start_transform*: Transform
      ## level.json: the spawn pose applied to every player at the PLAYERS
      ## load_order step (and, later, to mid-session joins).
    load_player_with_scripts*: bool
      ## level.json: reserved override for the persisted-unit-with-decoration-
      ## script edge case (reveal after the fast data render instead of
      ## waiting for the script). The gate currently always waits for
      ## ASAP-ended + settled; parsed and persisted so levels can opt in
      ## when the trim lands.
    load_order*: seq[string]
      ## The unit ids in level.json's load_order, as read at load. save_level
      ## regenerates the list but preserves this order where dependencies
      ## allow, appending genuinely new units at the end — so the order the
      ## level loads in (and, later, streams in) stays stable and authorable.
    frame_count*: int
    skip_block_paint*: bool
    disable_packed_chunks*: bool # Runtime toggle for packed chunk format
    open_sign_value*: EdValue[Sign]
    queued_action_value*: EdValue[string]
    scale_factor*: float
    worker_ctx_name*: string
    server_ctx_name_value*: EdValue[string]
      # Context running scripts (self if Server, remote otherwise)
    level_name_value*: EdValue[string]
    status_message_value*: EdValue[string]
    voxel_tasks_value*: EdValue[int]
    ignored_touches*: set[byte]
    logger*: proc(level, msg: string) {.gcsafe.}
    test_exit_code_value*: EdValue[int]
      # -1 = not set, 0 = success, 1+ = failure count
    net_bytes_sent_value*: EdValue[int64]
    net_bytes_received_value*: EdValue[int64]
    net_connections_value*: EdValue[int]
    ed_mem_value*: EdValue[int] # worker ctx resident body bytes (evictor)

  Model* = ref object of EdRef
    target_point*: Vector3
    target_normal*: Vector3
    local_flags*: EdSet[LocalModelFlags]
    global_flags*: EdSet[GlobalModelFlags]
    node*: Spatial

  Ground* = ref object of Model

  Shared* = ref object of EdRef
    materials* {.ed_ignore.}: seq[ShaderMaterial]
      ## Node-side Godot refs, shared across the unit tree's nodes.
      ## `ed_ignore`: godot refs can't ride a body sync — a revive would
      ## wipe them (and glow/highlight with them).
    emission_colors* {.ed_ignore.}: seq[godot.Color]
    edit_snapshots*: EdTable[EditKey, SnapshotData]
    edit_deltas*: EdTable[EditKey, EdSeq[DeltaUpdate]]
    palette*: EdSeq[Color]
      ## Static (non-named) voxel colors for this unit tree, in allocation
      ## order. A packed color_index >= STATIC_COLOR_BASE indexes this seq.
      ## Append-only; not persisted (edit JSON stores hex, load re-allocates).
    palette_cache* {.ed_ignore.}: Table[Color, int]
      ## Local color -> palette index cache; rebuilt when out of sync.
      ## `ed_ignore`: per-side state — syncing it would race concurrent
      ## lookups during body serialization.

  CachedChunk* = ref object
    ## One decoded chunk in a VoxelStore's read-through cache: the dense cell
    ## array composed from the synced tables (packed ⊕ deltas ⊕ pending).
    cells*: array[CHUNK_VOLUME, PackedVoxel]
    count*: int ## non-empty cells — the flush gate / has-voxels signal
    tick*: int ## LRU touch stamp (only enforced where cache_cap > 0)

  VoxelStore* = ref object
    # Local per-side render wrapper. The synced tables (`packed_chunks`,
    # `chunk_deltas`) are owned by the Build (Build Ed fields) and merely
    # referenced here; the rest (`chunk_cache`, `pending_*`, …) is local state
    # decoded on demand per side.
    ctx* {.cursor.}: EdContext
      # back-ref; the Build owns this VoxelStore, ctx outlives it
    thing_id*: string # For edit key construction
    immediate*: bool
      ## Apply draws straight to the synced `chunk_deltas`/`edit_deltas` tables
      ## instead of buffering into `pending_*` for a later `flush_dirty_*`. The
      ## app's worker batches through the buffer; an external client that draws
      ## without a flush loop sets this so its voxels sync as they're drawn —
      ## the same path the in-process "main" context already takes.
    # Back-ref to the owning Build (cursor — the Build outlives its wrapper). The
    # synced tables `packed_chunks`/`chunk_deltas` are read LIVE from it via procs
    # (see voxels.nim), not cached — a reload reincarnates those Ed fields, and a
    # cached copy would dangle on the destroyed table (ed revives the Build's
    # field in place, so reading through it always sees the current table).
    build* {.cursor.}: Build
    edit_snapshots*: EdTable[EditKey, SnapshotData]
    edit_deltas*: EdTable[EditKey, EdSeq[DeltaUpdate]]
    chunk_cache*: Table[Vector3, CachedChunk]
      ## Lazily decoded chunks (see `cached_chunk` in voxels.nim). Point reads
      ## and writes go through here; snapshot arrival invalidates, delta
      ## arrival pokes. Bulk iteration composes throwaway arrays instead so a
      ## full-build scan can't flush the hot set.
    cache_cap*: int
      ## Max cached chunks; 0 = unbounded. Small on main (bounded working
      ## set for interactive point queries); unbounded on the worker (its
      ## scripts and saves touch everything anyway).
    cache_tick*: int
    local_edits*: Table[Vector3, Table[Vector3, VoxelInfo]]
    pending_chunks*:
      Table[Vector3, seq[tuple[pos: Vector3, voxel: PackedVoxel]]]
    pending_snapshots*: Table[Vector3, SnapshotData]
      ## Whole chunks staged by the bulk load path (adopt_edit_chunks),
      ## published by the same paced flush_dirty_chunks the per-voxel buffer
      ## uses. Value = the stored blob to publish verbatim, or empty to
      ## re-encode from the cache (holes/deltas changed it). Publishing all
      ## chunks eagerly at load overshot the sync channel in one burst.
    pending_edits*: Table[Vector3, seq[tuple[pos: Vector3, voxel: PackedVoxel]]]
    on_chunk_created*: proc(chunk_id: Vector3) {.gcsafe.}
    snapshots_flushed*: int
    deltas_flushed*: int

  ColorIndexResolver* = proc(color_index: int): int64 {.gcsafe.}
    ## Maps a packed color_index to the voxel library slot the engine should
    ## render. Identity for named colors; static palette entries resolve to
    ## runtime-registered library slots.

  VoxelRenderer* = ref object
    voxel_tool*: VoxelTool
    resolver*: ColorIndexResolver
    buffer*: VoxelBuffer
    min_pos*: Vector3
    max_pos*: Vector3
    buffer_size*: Vector3
    dirty*: bool
    asap_active*: bool
    last_paste_time*: MonoTime

  ScriptErrors* =
    EdSeq[tuple[msg: string, info: TLineInfo, location: string, log: bool]]

  SightQuery* = object
    target*: Thing
    distance*: float
    answer*: Option[bool]

  Thing* = ref object of Model
    parent* {.cursor.}: Thing # back-ref; the parent owns this child via `things`
    things*: EdSeq[Thing]
    start_transform*: Transform
    scale_value*: EdValue[float]
    glow_value*: EdValue[float]
    speed_value*: EdValue[float]
    code_value*: EdValue[Code]
    script_ctx*: ScriptCtx
    disabled*: bool
    velocity_value*: EdValue[Vector3]
    transform_value*: EdValue[Transform]
    clone_of*: Thing
    spawned_by*: string
      ## Id of the thing whose script `.new()`'d this instance, set once at
      ## creation and never changed. Distinguishes *my* instances from foreign
      ## ones (both have `clone_of`): when a thing is destroyed, only children
      ## with `spawned_by == self.id` go down with it; everything else (real
      ## things, the player, instances spawned elsewhere) is re-rooted.
    collisions*: EdSeq[tuple[id: string, normal: Vector3]]
    shared_value*: EdValue[Shared]
    start_color*: Color
    color_value*: EdValue[Color]
    sight_ray*: RayCast
    frame_created*: int
    errors*: ScriptErrors
    current_line_value*: EdValue[int]
    sight_query_value*: EdValue[SightQuery]
    eval_value*: EdValue[string]
    anchor_value*: EdValue[Transform]
    rendered_voxel_count_value*: EdValue[int]
    pending_block_updates_value*: EdValue[int]
    query_value*: EdValue[ThingQuery]
    owner_ctx_value*: EdValue[string]
      # ctx id that created the thing, synced so the authority can reap EPHEMERAL
      # things when that context drops -- without encoding the ctx in the id.

  BlockLogEntry* =
    tuple[
      thing_id: string,
      color: Color,
      local_position: Vector3,
      global_position: Vector3,
      timestamp: MonoTime,
    ]

  Player* = ref object of Thing
    colliders*: HashSet[Model]
    rotation_value*: EdValue[float]
    boost_value*: EdValue[Vector3]
      ## Script-driven launch impulse (player.boost). Touched, not set, so
      ## identical repeat boosts still fire; the player node consumes it in
      ## its physics step (the walk controller rebuilds horizontal velocity
      ## from input every frame, so a plain velocity write can't launch).
    input_direction_value*: EdValue[Vector3]
    cursor_position_value*: EdValue[tuple[line: int, col: int]]
    block_log_entries*: EdSeq[BlockLogEntry]

  Bot* = ref object of Thing
    animation_value*: EdValue[string]

  Sign* = ref object of Thing
    message_value*, more_value*: EdValue[string]
    width_value*, height_value*: EdValue[float]
    size_value*: EdValue[int]
    billboard_value*: EdValue[bool]
    owner_value*: EdValue[Thing]
    text_only*: bool

  Build* = ref object of Thing
    # The synced voxel tables ride the build's closure as real Ed fields (like
    # `things`) — reconnected by reference after sync, with generated ids. So they
    # need no id lookup, and a reload gets fresh ids (no destroy+recreate-same-id
    # race). `voxels` is the LOCAL render wrapper (rebuilt per-side) that points
    # at these.
    packed_chunks*: EdTable[Vector3, SnapshotData]
    chunk_deltas*: EdTable[Vector3, EdSeq[DeltaUpdate]]
    voxels*: VoxelStore
    draw_transform_value*: EdValue[Transform]
    # draw_transform mirrored for the render side (turtle indicator). A separate
    # field because draw_transform is written per voxel — syncing it directly
    # would flood the context queue during ASAP draws. This one is written once
    # per batch (see sync_turtle).
    turtle_transform_value*: EdValue[Transform]
    voxels_per_frame*: float
    voxels_remaining_this_frame*: float
    # `speed = auto` ramp state (see builds.nim). `active` while the draw rate
    # is ramping up, `started` once the first block anchors the clock, `done`
    # after it has handed off to ASAP — so a later `speed = auto` (e.g. an
    # `asap:` block restoring the speed) doesn't restart a finished ramp.
    auto_ramp_active*: bool
    auto_ramp_started*: bool
    auto_ramp_done*: bool
    auto_ramp_start*: MonoTime
    drawing*: bool
    bounds_value*: EdValue[AABB]
    bot_collisions*: bool
    frames*: EdTable[int, FrameData]
      ## Saved animation frames, keyed by dense 0-based index (the Build API
      ## keeps keys contiguous). A table rather than a seq so replace is one
      ## keyed op — ed's positional seq ops don't sync order-safely. Synced
      ## once as data; playback only moves `current_frame`.
    frames_dirty*: bool
      ## Frames changed since the last save_frames (host-local, not synced).
      ## Loaded frames start clean: re-encoding 24 untouched frames on every
      ## level save dominated debug-build load times.
    current_frame_value*: EdValue[int]
      ## Displayed frame, or -1 for the live voxel state. Display-only:
      ## queries and collisions keep reading the live voxels (use
      ## `load_frame` to actually restore a frame for editing).
    frames_fps_value*: EdValue[float]
      ## > 0 while playing; the server advances `current_frame` at this rate.
    frames_loop_value*: EdValue[bool]
    sealed_frames_value*: EdValue[bool]
      ## Bake frame meshes self-contained: chunk borders treated as open,
      ## so every chunk mesh carries its own boundary skin and any mix of
      ## displayed frames is visually closed — no seams, ever, at the cost
      ## of ~a third more (invisible, backface-culled) border quads and no
      ## neighbor-aware ambient occlusion at chunk edges. Off: meshes bake
      ## against the frame's real neighbor content — fewer quads, exact AO,
      ## but chunks displaying different frames (temporal LOD bands,
      ## catch-up after movement) can show transient seams.
    cull_down_faces_value*: EdValue[bool]
      ## Sheet hint: skip downward faces when meshing. An ocean slab's
      ## underside is never visible but costs ~a third of its geometry.
      ## Set it before drawing/playing — cached frame meshes don't rebake.

  Config* = object
    font_size*: int
    world*: string
    level*: string
    toolbar_size*: float
    show_stats*: bool
    megapixels*: float
    megapixels_override*: float
    environment*: string
    environment_override*: string
    world_dir*: string
    level_dir*: string
    data_dir*: string
    script_dir*: string
    scene*: string
    lib_dir*: string
    full_screen*: bool
    semicolon_as_colon*: bool
    listen_address*: string
    listen_address_override*: string
    connect_address*: string
    connect_address_override*: string
    run_server*: bool
    player_color*: Color
    work_dir*: string
    walk_speed*: int
    fly_speed*: int
    alt_walk_speed*: int
    alt_fly_speed*: int
    mouse_sensitivity*: float
    gamepad_sensitivity*: float
    invert_gamepad_y_axis*: bool
    screen_scale*: float
    auto_show_console*: bool

  UserConfig* = object
    font_size*: Option[int]
    toolbar_size*: Option[float]
    world*: Option[string]
    level*: Option[string]
    environment*: Option[string]
    show_stats*: Option[bool]
    god_mode*: Option[bool]
    megapixels*: Option[float]
    full_screen*: Option[bool]
    semicolon_as_colon*: Option[bool]
    run_server*: Option[bool]
    player_color*: Option[colortypes.Color]
    walk_speed*: Option[int]
    fly_speed*: Option[int]
    alt_walk_speed*: Option[int]
    alt_fly_speed*: Option[int]
    mouse_sensitivity*: Option[float]
    gamepad_sensitivity*: Option[float]
    invert_gamepad_y_axis*: Option[bool]
    listen_address*: Option[string]
    connect_address*: Option[string]
    auto_show_console*: Option[bool]

  Code* = object
    owner*: string
    runner*: string
    nim*: string

  ScriptCtx* = ref object
    script*: string
    timer*: MonoTime
    # Instruction budget for the non-yielding-script watchdog: decremented by
    # the VM exec hook, TIMEOUT when exhausted. Deterministic (the same script
    # costs the same count on any machine or build type), unlike the wall-clock
    # deadline it replaces — a cold or busy machine could stall a legitimate
    # compile past any wall-clock limit, and a timeout aborting a module load
    # poisons the interpreter's import graph.
    fuel*: int64
    # Immediate draw calls (box/sphere/cylinder/draw_voxel) since the last
    # yield. The logo APIs yield naturally (they animate in-engine); the
    # immediate APIs do all their work in the bridged call, so a build script
    # could otherwise run its whole control flow in one unyielding resume.
    # Every draw_yield_interval calls the bridge requests a pause — bounding
    # the worker stall per resume and re-arming `fuel` on resume, so no
    # legitimate drawing script can exhaust the budget.
    unyielded_draws*: int
    ctx: PCtx
    pc: int
    tos: PStackFrame
    current_line*: TLineInfo
    previous_line: TLineInfo
    pause_requested: bool
    module_name*: string
    file_name*: string
    exit_code*: Option[int]
    callback*: Callback
    saved_callback*: Callback
    action_running*: bool
    running*: bool
    interpreter*: Interpreter
    code*: string
    pass_context*: PContext
    last_ran*: MonoTime
    file_index*: int
    dependencies*: seq[string]
    last_saved_mtime*: Time
    last_saved_json_mtime*: Time

  VMError* = object of CatchableError
  QuitKind* = enum
    UNKNOWN
    TIMEOUT

  VMQuit* = object of VMError
    info*: TLineInfo
    kind*: QuitKind
    location*: string

  VMPause* = object of CatchableError

  Callback* = proc(delta: float, timeout: MonoTime): TaskStates {.gcsafe.}

  ScriptController* = ref object
    worker_thread*: system.Thread[tuple[ctx: EdContext, state: GameState]]

  Worker* = ref object
    # Things that arrived before their data (narrow partial replica): the worker
    # join is deferred until their core containers fill. Drained per loop tick.
    pending_things*: seq[Thing]
    retry_failures*: bool
    interpreter*: Interpreter
    active_thing*: Thing
    thing_map*: Table[PNode, Thing]
    node_map*: Table[Thing, PNode]
    template_node_map*: Table[string, PNode]
    failed*: seq[tuple[thing: Thing, e: ref VMQuit]]
    last_exception*: ref Exception
    player_cache*: Table[string, Player]
    module_names*: HashSet[string]
    watch_files_at*: MonoTime
    orphan_scripts_reported*: HashSet[string]
    eval_proc*: proc(
      code: string, top_level: bool, thing_id: string
    ): tuple[result: string, error: string] {.gcsafe.}
    update_files_proc*: proc() {.gcsafe.}
    # Test-mode result accounting, aggregated across all scripts as they
    # report (see report_test_results). Membership of state.things is not a
    # reliable "are we done" signal in test mode — the ed sync layer removes
    # finished test things — so completion is inferred from quiescence
    # (test_last_activity) and the exit code from these running totals.
    test_pass_count*: int
    test_fail_count*: int
    test_run_count*: int
    test_error_count*: int # scripts that failed to load/run (permanent)
    test_report_count*: int # scripts that reported a summary
    test_last_activity*: MonoTime

  NodeController* = ref object
    # Things that arrived before their data (narrow partial replica): the scene
    # add is deferred until their core containers fill. Drained per frame.
    pending*: seq[Thing]

  SavedState* = object
    transform*: Transform
    rotation*: float
    flags*: set[LocalStateFlags]
    restarting*: bool
    connect_address*: string
    error_message*: string

proc from_flatty*[N: NimGodotObject](s: string, i: var int, n: N) =
  discard

proc to_flatty*[N: NimGodotObject](s: var string, n: N) =
  discard

proc from_flatty*(s: string, i: var int, n: var ScriptCtx) =
  discard

proc to_flatty*(s: var string, n: ScriptCtx) =
  discard

proc from_flatty*(s: string, i: var int, n: var EdContext) =
  discard

proc to_flatty*(s: var string, n: EdContext) =
  discard

proc packed_chunks*(self: VoxelStore): EdTable[Vector3, SnapshotData] =
  ## Read the Build's table live — never cache it: a reload reincarnates the Ed
  ## field (ed revives it in place), so reading through the Build always sees the
  ## current table; a cached copy would dangle on the destroyed one.
  self.build.packed_chunks

proc chunk_deltas*(self: VoxelStore): EdTable[Vector3, EdSeq[DeltaUpdate]] =
  self.build.chunk_deltas

Ed.register(Player)
Ed.register(Build)
Ed.register(Sign)
Ed.register(Bot)
Ed.register(Shared)
Ed.build_accessors(GameState)
