import std/[tables, monotimes, times, sets, options, macros]

type
  # A general way to run a query against a unit from another context (another
  # thread, or a remote process over the network). The asker fills in a
  # UnitQuery and sets the unit's `query` to it with state QUERY_PENDING; the
  # context that owns the unit's behavior answers by writing the same value
  # back with `result`/`error` filled in and state QUERY_DONE. Today only
  # AGENT bots subscribe for answers (see bots.nim and bot_node.nim), but the
  # slot exists on every unit.
  UnitQueryKind* = enum
    QUERY_BLANK
    QUERY_SCREENSHOT
    QUERY_EVAL
    QUERY_CONSOLE
    QUERY_LEVEL_DIR
    QUERY_PING

  UnitQueryState* = enum
    QUERY_IDLE
    QUERY_PENDING
    QUERY_READY
    QUERY_DONE

  UnitQuery* = object
    kind*: UnitQueryKind
    code*: string
    result*: string
    error*: string
    state*: UnitQueryState
    top_level*: bool
    unit_id*: string
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
  EMPTY_VOXEL* = 0'u8

  # Delta thresholds
  MAX_CHANGES_FOR_DELTA* = 100
  MAX_DELTAS_BEFORE_SNAPSHOT* = 100

type
  PackedVoxel* = uint8

  SnapshotData* = object
    data*: string

  DeltaUpdate* = object
    data*: string

  PackedChunk* = SnapshotData # Legacy alias

  VoxelKind* = enum
    HOLE
    MANUAL
    COMPUTED

  VoxelInfo* = tuple[kind: VoxelKind, color: Color]

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

  GlobalStateFlags* = enum
    LOADING_LEVEL

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
    AGENT
      ## Set on units owned by a remote client context — the human's
      ## Player and any client-owned bot (MCP, scripted agents). Agent
      ## units survive level reloads (peer to the human), are skipped
      ## by level persistence (their lifecycle is the client's, not
      ## the level's), and get cleaned up when their owning context
      ## unsubscribes. Convention: agent unit ids contain the owning
      ## context name as a substring (e.g. `player-{ctx_name}`,
      ## `mcp_bot-{ctx_name}`) so worker.nim can match them on
      ## unsubscribe.
    VIEWER
      ## The unit streams voxel terrain around itself: the server attaches
      ## a VoxelViewer node so chunks near the unit get meshed even when no
      ## player is nearby. Off by default — players bring their own viewer,
      ## and most units don't need one. Set it on agent bots that take
      ## screenshots away from the player.

  Tools* = enum
    CODE_MODE
    BLUE_BLOCK
    RED_BLOCK
    GREEN_BLOCK
    BLACK_BLOCK
    WHITE_BLOCK
    BROWN_BLOCK
    PLACE_BOT
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
    open_unit_value*: EdValue[Unit]
    tool_value*: EdValue[Tools]
    gravity*: float
    nodes*: tuple[game: Node, data: Node, player: Node]
    screenshot_camera*: Node
    screenshot_viewport*: Node
    player_camera*: Node
    screenshot_counter*: int
    player_value*: EdValue[Player]
    units*: EdSeq[Unit]
    ground*: Ground
    draw_unit_id*: string
    console*: ConsoleModel
    paused*: bool
    show_prototypes*: bool
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
    materials*: seq[ShaderMaterial]
    emission_colors*: seq[godot.Color]
    edit_snapshots*: EdTable[EditKey, SnapshotData]
    edit_deltas*: EdTable[EditKey, EdSeq[DeltaUpdate]]

  VoxelStore* = ref object
    # Local per-side render wrapper. The synced tables (`packed_chunks`,
    # `chunk_deltas`) are owned by the Build (Build Ed fields) and merely
    # referenced here; the rest (`local_voxels`, `pending_*`, …) is local state
    # rebuilt on each side.
    ctx* {.cursor.}: EdContext # back-ref; the Build owns this VoxelStore, ctx outlives it
    unit_id*: string # For edit key construction
    # Back-ref to the owning Build (cursor — the Build outlives its wrapper). The
    # synced tables `packed_chunks`/`chunk_deltas` are read LIVE from it via procs
    # (see voxels.nim), not cached — a reload reincarnates those Ed fields, and a
    # cached copy would dangle on the destroyed table (ed revives the Build's
    # field in place, so reading through it always sees the current table).
    build* {.cursor.}: Build
    edit_snapshots*: EdTable[EditKey, SnapshotData]
    edit_deltas*: EdTable[EditKey, EdSeq[DeltaUpdate]]
    local_voxels*: Table[Vector3, Table[Vector3, VoxelInfo]]
    local_edits*: Table[Vector3, Table[Vector3, VoxelInfo]]
    pending_chunks*:
      Table[Vector3, seq[tuple[pos: Vector3, voxel: PackedVoxel]]]
    pending_edits*: Table[Vector3, seq[tuple[pos: Vector3, voxel: PackedVoxel]]]
    block_count*: int
    on_chunk_created*: proc(chunk_id: Vector3) {.gcsafe.}
    snapshots_flushed*: int
    deltas_flushed*: int

  VoxelRenderer* = ref object
    voxel_tool*: VoxelTool
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
    target*: Unit
    distance*: float
    answer*: Option[bool]

  Unit* = ref object of Model
    parent* {.cursor.}: Unit # back-ref; the parent owns this child via `units`
    units*: EdSeq[Unit]
    start_transform*: Transform
    scale_value*: EdValue[float]
    glow_value*: EdValue[float]
    speed*: float
    code_value*: EdValue[Code]
    script_ctx*: ScriptCtx
    disabled*: bool
    velocity_value*: EdValue[Vector3]
    transform_value*: EdValue[Transform]
    clone_of*: Unit
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
    query_value*: EdValue[UnitQuery]

  BlockLogEntry* = tuple
    unit_id: string
    color: Colors
    local_position: Vector3
    global_position: Vector3
    timestamp: MonoTime

  Player* = ref object of Unit
    colliders*: HashSet[Model]
    rotation_value*: EdValue[float]
    input_direction_value*: EdValue[Vector3]
    cursor_position_value*: EdValue[tuple[line: int, col: int]]
    block_log_entries*: EdSeq[BlockLogEntry]

  Bot* = ref object of Unit
    animation_value*: EdValue[string]

  Sign* = ref object of Unit
    message_value*, more_value*: EdValue[string]
    width_value*, height_value*: EdValue[float]
    size_value*: EdValue[int]
    billboard_value*: EdValue[bool]
    owner_value*: EdValue[Unit]
    text_only*: bool

  Build* = ref object of Unit
    # The synced voxel tables ride the build's closure as real Ed fields (like
    # `units`) — reconnected by reference after sync, with generated ids. So they
    # need no id lookup, and a reload gets fresh ids (no destroy+recreate-same-id
    # race). `voxels` is the LOCAL render wrapper (rebuilt per-side) that points
    # at these.
    packed_chunks*: EdTable[Vector3, SnapshotData]
    chunk_deltas*: EdTable[Vector3, EdSeq[DeltaUpdate]]
    voxels*: VoxelStore
    draw_transform_value*: EdValue[Transform]
    voxels_per_frame*: float
    voxels_remaining_this_frame*: float
    drawing*: bool
    save_points*:
      Table[string, tuple[position: Transform, color: Color, drawing: bool]]
    bounds_value*: EdValue[AABB]
    bot_collisions*: bool

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
    # Units that arrived before their data (narrow partial replica): the worker
    # join is deferred until their core containers fill. Drained per loop tick.
    pending_units*: seq[Unit]
    retry_failures*: bool
    interpreter*: Interpreter
    active_unit*: Unit
    unit_map*: Table[PNode, Unit]
    node_map*: Table[Unit, PNode]
    template_node_map*: Table[string, PNode]
    failed*: seq[tuple[unit: Unit, e: ref VMQuit]]
    last_exception*: ref Exception
    player_cache*: Table[string, Player]
    module_names*: HashSet[string]
    watch_files_at*: MonoTime
    orphan_scripts_reported*: HashSet[string]
    eval_proc*: proc(code: string, top_level: bool, unit_id: string): tuple[
      result: string, error: string
    ] {.gcsafe.}
    update_files_proc*: proc() {.gcsafe.}

  NodeController* = ref object
    # Units that arrived before their data (narrow partial replica): the scene
    # add is deferred until their core containers fill. Drained per frame.
    pending*: seq[Unit]

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
