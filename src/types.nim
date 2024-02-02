import std/[tables, monotimes, sets, options, macros]
import godotapi/[spatial, ray_cast]
import pkg/core/godotcoretypes except Color
import pkg/core/[vector3, basis, aabb, godotbase]
import pkg/compiler/[ast, lineinfos, semdata]
import pkg/[model_citizen]
import models/colors, libs/[eval]

from pkg/godot import NimGodotObject

export Vector3, Transform, vector3, basis, AABB, aabb
export godotbase except print
export Interpreter

type
  EnuError* = object of CatchableError
  LocalStateFlags* = enum
    CommandMode
    EditorVisible
    ConsoleVisible
    BlockTargetVisible
    ReticleVisible
    DocsVisible
    MouseCaptured
    PrimaryDown
    SecondaryDown
    EditorFocused
    ConsoleFocused
    DocsFocused
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

  GlobalStateFlags* = enum
    LoadingLevel

  LocalModelFlags* = enum
    Hover
    TargetMoved
    Highlight
    HighlightError
    Hide

  GlobalModelFlags* = enum
    Global
    Visible
    Lock
    Ready
    ScriptInitializing
    Dirty
    Resetting

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
    open_sign_value*: ZenValue[Sign]
    queued_action_value*: ZenValue[string]
    scale_factor*: float
    worker_ctx_name*: string
    level_name_value*: ZenValue[string]
    status_message_value*: ZenValue[string]
    voxel_tasks_value*: ZenValue[int]

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

  ScriptErrors* = ZenSeq[tuple[msg: string, info: TLineInfo, location: string]]

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

  Build* = ref object of Unit
    chunks*: ZenTable[Vector3, Chunk]
    draw_transform_value*: ZenValue[Transform]
    voxels_per_frame*: float
    voxels_remaining_this_frame*: float
    drawing*: bool
    save_points*:
      Table[string, tuple[position: Transform, color: Color, drawing: bool]]
    bounds_value*: ZenValue[AABB]
    bot_collisions*: bool
    batching*: bool
    batched_voxels*: Table[Vector3, Table[Vector3, VoxelInfo]]

  Config* = object
    font_size*: int
    world*: string
    level*: string
    dock_icon_size*: float
    show_stats*: bool
    mega_pixels*: float
    world_dir*: string
    level_dir*: string
    data_dir*: string
    script_dir*: string
    scene*: string
    lib_dir*: string
    start_full_screen*: bool
    semicolon_as_colon*: bool
    listen_address*: string
    connect_address*: string
    player_color*: Color
    work_dir*: string
    walk_speed*: int
    fly_speed*: int
    alt_walk_speed*: int
    alt_fly_speed*: int
    mouse_sensitivity*: float
    gamepad_sensitivity*: float
    invert_gamepad_y_axis*: bool

  UserConfig* = object
    font_size*: Option[int]
    dock_icon_size*: Option[float]
    world*: Option[string]
    level*: Option[string]
    show_stats*: Option[bool]
    god_mode*: Option[bool]
    mega_pixels*: Option[float]
    start_full_screen*: Option[bool]
    semicolon_as_colon*: Option[bool]
    listen_address*: Option[string]
    connect_address*: Option[string]
    player_color*: Option[colortypes.Color]
    walk_speed*: Option[int]
    fly_speed*: Option[int]
    alt_walk_speed*: Option[int]
    alt_fly_speed*: Option[int]
    mouse_sensitivity*: Option[float]
    gamepad_sensitivity*: Option[float]
    invert_gamepad_y_axis*: Option[bool]

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
    watch_active*: bool
    active_unit*: Unit
    unit_map*: Table[PNode, Unit]
    node_map*: Table[Unit, PNode]
    failed*: seq[tuple[unit: Unit, e: ref VMQuit]]
    last_exception*: ref Exception

  NodeController* = ref object

proc from_flatty*[N: NimGodotObject](s: string, i: var int, n: N) =
  discard

proc to_flatty*[N: NimGodotObject](s: var string, n: N) =
  discard

proc from_flatty*(s: string, i: var int, n: var ScriptCtx) =
  discard

proc to_flatty*(s: var string, n: ScriptCtx) =
  discard

Zen.register(Player)
Zen.register(Build)
Zen.register(Sign)
Zen.register(Bot)
Zen.register(Shared)
Zen.build_accessors(GameState)
