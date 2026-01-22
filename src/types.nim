import std/[tables, monotimes, sets, options, macros]
import godotapi/[spatial, ray_cast]
import pkg/core/godotcoretypes except Color
import pkg/core/[vector3, basis, aabb, godotbase]
import pkg/compiler/[ast, lineinfos, semdata]
import ed
import models/colors, libs/[eval]

from pkg/godot import NimGodotObject

export Vector3, Transform, vector3, basis, AABB, aabb
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
    SCRIPT_RUNNING
    DIRTY
    RESETTING
    HIGHLIGHT_ERROR
    ASAP_MODE

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
    player_value*: EdValue[Player]
    units*: EdSeq[Unit]
    ground*: Ground
    draw_unit_id*: string
    console*: ConsoleModel
    paused*: bool
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

  Model* = ref object of RootObj
    id*: string
    target_point*: Vector3
    target_normal*: Vector3
    local_flags*: EdSet[LocalModelFlags]
    global_flags*: EdSet[GlobalModelFlags]
    node*: Spatial

  Ground* = ref object of Model

  Shared* = ref object of RootObj
    id*: string
    materials*: seq[ShaderMaterial]
    emission_colors*: seq[godot.Color]
    edit_snapshots*: EdTable[EditKey, SnapshotData]
    edit_deltas*: EdTable[EditKey, EdSeq[DeltaUpdate]]

  VoxelStore* = ref object
    id*: string
    ctx*: EdContext
    unit_id*: string # For edit key construction

    # Regular chunks (owned)
    packed_chunks*: EdTable[Vector3, SnapshotData]
    chunk_deltas*: EdTable[Vector3, EdSeq[DeltaUpdate]]

    # Edits - references to tables in Shared (not owned)
    edit_snapshots*: EdTable[EditKey, SnapshotData]
    edit_deltas*: EdTable[EditKey, EdSeq[DeltaUpdate]]

    # Local caches (plain Tables)
    local_voxels*: Table[Vector3, Table[Vector3, VoxelInfo]]
    local_edits*: Table[Vector3, Table[Vector3, VoxelInfo]]

    # Pending changes
    pending_chunks*: Table[Vector3, seq[tuple[pos: Vector3, voxel: PackedVoxel]]]
    pending_edits*: Table[Vector3, seq[tuple[pos: Vector3, voxel: PackedVoxel]]]

    block_count*: int

    # Callback when a new chunk is created (for bounds expansion)
    on_chunk_created*: proc(chunk_id: Vector3) {.gcsafe.}

    # Stats
    snapshots_flushed*: int
    deltas_flushed*: int

  ScriptErrors* =
    EdSeq[tuple[msg: string, info: TLineInfo, location: string, log: bool]]

  SightQuery* = object
    target*: Unit
    distance*: float
    answer*: Option[bool]

  Unit* = ref object of Model
    parent*: Unit
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
    eids* {.ed_ignore.}: seq[EID]
    errors*: ScriptErrors
    current_line_value*: EdValue[int]
    sight_query_value*: EdValue[SightQuery]
    eval_value*: EdValue[string]

  Player* = ref object of Unit
    colliders*: HashSet[Model]
    rotation_value*: EdValue[float]
    input_direction_value*: EdValue[Vector3]
    cursor_position_value*: EdValue[tuple[line: int, col: int]]

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
    connect_address*: string
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
    timeout_at*: MonoTime
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
    dependents*: HashSet[string]
    pass_context*: PContext
    last_ran*: MonoTime
    file_index*: int

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
    retry_failures*: bool
    interpreter*: Interpreter
    module_names*: HashSet[string]
    active_unit*: Unit
    unit_map*: Table[PNode, Unit]
    node_map*: Table[Unit, PNode]
    template_node_map*: Table[string, PNode]
    failed*: seq[tuple[unit: Unit, e: ref VMQuit]]
    last_exception*: ref Exception
    player_cache*: Table[string, Player]
    initial_load_done*: bool

  NodeController* = ref object

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

Ed.register(Player)
Ed.register(Build)
Ed.register(Sign)
Ed.register(Bot)
Ed.register(Shared)
Ed.build_accessors(GameState)
