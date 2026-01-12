import std/[tables, monotimes, sets, options, macros]
import godotapi/[spatial, ray_cast]
import pkg/core/godotcoretypes except Color
import pkg/core/[vector3, basis, aabb, godotbase]
import pkg/compiler/[ast, lineinfos, semdata]
import pkg/[model_citizen]
import models/[colors, packed_chunks], libs/[eval]

from pkg/godot import NimGodotObject

export Vector3, Transform, vector3, basis, AABB, aabb
export godotbase except print
export Interpreter
export lineinfos.`==`

type
  EnuError* = object of CatchableError
  ResourceLimitError* = object of CatchableError
  LocalStateFlags* = enum
    CommandMode
    EditorVisible
    ConsoleVisible
    BlockTargetVisible
    ReticleVisible
    DocsVisible
    SettingsVisible
    MouseCaptured
    PrimaryDown
    SecondaryDown
    EditorFocused
    ConsoleFocused
    DocsFocused
    SettingsFocused
    ViewportFocused
    Playing
    Flying
    God
    AltWalkSpeed
    AltFlySpeed
    LoadingScript
    Server
    Quitting
    ResettingVM
    NeedsRestart
    Connecting
    SceneReady
    TouchControls
    FullWidthPanels
    EditorOpening
    EditorClosing
    TestMode

  GlobalStateFlags* = enum
    LoadingLevel

  LocalModelFlags* = enum
    Hover
    TargetMoved
    Highlight
    Hide

  GlobalModelFlags* = enum
    Global
    Visible
    Lock
    Ready
    ScriptInitializing
    ScriptRunning
    Dirty
    Resetting
    HighlightError

  Tools* = enum
    CodeMode
    BlueBlock
    RedBlock
    GreenBlock
    BlackBlock
    WhiteBlock
    BrownBlock
    PlaceBot
    Disabled

  TaskStates* = enum
    Running
    Done
    NextTask

  ConsoleModel* = ref object
    log*: ZenSeq[string]

  GameState* = ref object
    local_flags*: ZenSet[LocalStateFlags]
    wants*: ZenSeq[LocalStateFlags]
    global_flags*: ZenSet[GlobalStateFlags]
    config_value*: ZenValue[Config]
    open_unit_value*: ZenValue[Unit]
    tool_value*: ZenValue[Tools]
    gravity*: float
    nodes*: tuple[game: Node, data: Node, player: Node]
    player_value*: ZenValue[Player]
    units*: ZenSeq[Unit]
    ground*: Ground
    draw_unit_id*: string
    console*: ConsoleModel
    paused*: bool
    frame_count*: int
    skip_block_paint*: bool
    disable_packed_chunks*: bool # Runtime toggle for packed chunk format
    use_chunk_buffers* = true
      # EXPERIMENT: Set to true for 20-second paste test
      # Use VoxelBuffer+paste instead of voxel_tool.set_voxel
    open_sign_value*: ZenValue[Sign]
    queued_action_value*: ZenValue[string]
    scale_factor*: float
    worker_ctx_name*: string
    level_name_value*: ZenValue[string]
    status_message_value*: ZenValue[string]
    voxel_tasks_value*: ZenValue[int]
    ignored_touches*: set[byte]
    logger*: proc(level, msg: string) {.gcsafe.}
    test_exit_code_value*: ZenValue[int]
      # -1 = not set, 0 = success, 1+ = failure count
    net_bytes_sent_value*: ZenValue[int64]
    net_bytes_received_value*: ZenValue[int64]
    net_connections_value*: ZenValue[int]

  Model* = ref object of RootObj
    id*: string
    target_point*: Vector3
    target_normal*: Vector3
    local_flags*: ZenSet[LocalModelFlags]
    global_flags*: ZenSet[GlobalModelFlags]
    node*: Spatial

  Ground* = ref object of Model

  Shared* = ref object of RootObj
    id*: string
    materials*: seq[ShaderMaterial]
    emission_colors*: seq[godot.Color]
    edits*: ZenTable[string, ZenTable[Vector3, VoxelInfo]]

  ScriptErrors* =
    ZenSeq[tuple[msg: string, info: TLineInfo, location: string, log: bool]]

  SightQuery* = object
    target*: Unit
    distance*: float
    answer*: Option[bool]

  Unit* = ref object of Model
    parent*: Unit
    units*: ZenSeq[Unit]
    start_transform*: Transform
    scale_value*: ZenValue[float]
    glow_value*: ZenValue[float]
    speed*: float
    code_value*: ZenValue[Code]
    script_ctx*: ScriptCtx
    disabled*: bool
    velocity_value*: ZenValue[Vector3]
    transform_value*: ZenValue[Transform]
    clone_of*: Unit
    collisions*: ZenSeq[tuple[id: string, normal: Vector3]]
    shared_value*: ZenValue[Shared]
    start_color*: Color
    color_value*: ZenValue[Color]
    sight_ray*: RayCast
    frame_created*: int
    zids* {.zen_ignore.}: seq[ZID]
    errors*: ScriptErrors
    current_line_value*: ZenValue[int]
    sight_query_value*: ZenValue[SightQuery]
    eval_value*: ZenValue[string]

  Player* = ref object of Unit
    colliders*: HashSet[Model]
    rotation_value*: ZenValue[float]
    input_direction_value*: ZenValue[Vector3]
    cursor_position_value*: ZenValue[tuple[line: int, col: int]]

  Bot* = ref object of Unit
    animation_value*: ZenValue[string]

  Sign* = ref object of Unit
    message_value*, more_value*: ZenValue[string]
    width_value*, height_value*: ZenValue[float]
    size_value*: ZenValue[int]
    billboard_value*: ZenValue[bool]
    owner_value*: ZenValue[Unit]
    text_only*: bool

  VoxelKind* = enum
    Hole
    Manual
    Computed

  VoxelInfo* = tuple[kind: VoxelKind, color: Color]

  Chunk* = ZenTable[Vector3, VoxelInfo]

  VoxelStore* = ref object
    id*: string
    disable_packed*: bool
    ctx*: ZenContext
    model*: Unit # Owning unit for watch lifetime binding

    # Core storage
    chunks*: ZenTable[Vector3, Chunk]
    block_count*: int

    # Packed format fields (used when state.disable_packed_chunks = false)
    packed_chunks*: ZenTable[Vector3, SnapshotData]
    chunk_deltas*: ZenTable[Vector3, ZenSeq[DeltaUpdate]]
    dirty_chunks*: HashSet[Vector3]
    last_snapshot*: Table[Vector3, Table[Vector3, PackedVoxel]]
    pending_flush_time*: Table[Vector3, MonoTime] # When chunk first became dirty
    pending_change_count*: Table[Vector3, int] # Changes since last flush

    # Batching
    batching*: bool
    batched_voxels*: Table[Vector3, Table[Vector3, VoxelInfo]]

    # Callbacks for Build integration
    on_chunk_created*: proc(chunk_id: Vector3) {.gcsafe.}

    # Stats tracking
    content_bytes*: int # Actual voxel data bytes (snapshots + deltas)

  Build* = ref object of Unit
    voxels*: VoxelStore
    draw_transform_value*: ZenValue[Transform]
    voxels_per_frame*: float
    voxels_remaining_this_frame*: float
    drawing*: bool
    save_points*:
      Table[string, tuple[position: Transform, color: Color, drawing: bool]]
    bounds_value*: ZenValue[AABB]
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
    Unknown
    Timeout

  VMQuit* = object of VMError
    info*: TLineInfo
    kind*: QuitKind
    location*: string

  VMPause* = object of CatchableError

  Callback* = proc(delta: float, timeout: MonoTime): TaskStates {.gcsafe.}

  ScriptController* = ref object
    worker_thread*: system.Thread[tuple[ctx: ZenContext, state: GameState]]

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

proc from_flatty*(s: string, i: var int, n: var ZenContext) =
  discard

proc to_flatty*(s: var string, n: ZenContext) =
  discard

Zen.register(Player)
Zen.register(Build)
Zen.register(Sign)
Zen.register(Bot)
Zen.register(Shared)
Zen.build_accessors(GameState)
