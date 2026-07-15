import std/[tables, random, macros]

var global_default* = false

const yes* = true
const no* = false
const ASAP* = 0.0
  ## Magic speed value. `speed = ASAP` makes a build draw everything at
  ## once instead of block by block.

const auto* = float.high
  ## The default build speed. `speed = auto` starts slow and speeds the
  ## drawing up over a few seconds, then finishes the rest all at once
  ## (`ASAP`). Set a plain number for a steady speed instead.

type
  Vector3* = tuple[x, y, z: float]
    ## A spot (or a direction) in the world. `x` is left/right, `y` is
    ## up/down, and `z` is forward/back.

  Basis* = tuple[x, y, z: Vector3]

  Transform* = tuple[basis: Basis, origin: Vector3]

  Pen* = tuple[position: Transform, color: Color, drawing: bool]
    ## A build's drawing context — turtle pose, color, pen-down state.
    ## `var spot = pen` captures it; `pen = spot` returns there. A plain
    ## tuple for now; it will grow into an object.

  WorldBox* = tuple[min, max: Vector3]
    ## An invisible box around a thing, described by its lowest corner
    ## and its highest corner. Used to check what fits where.

  Directions* = enum
    ## The 6 directions a thing can move, turn or lean. Each one has a
    ## single-letter shorthand, so `turn r` means `turn right`.
    up
    u
    down
    d
    left
    l
    right
    r
    forward
    f
    back
    b

  Thing* = ref object of RootObj
    ## Anything that exists in the world: a build, a bot, a sign, or
    ## the player. Most commands work on any thing.
    id: int
    name*: string
    advance_state_machine*: proc(): bool
    rng: Rand
    seed: int
    sign*: Sign
    query_results*: Table[string, seq[Thing]]

  Query*[T] = object of RootObj
    ## The answer to a question like `Bot.all` or `?player`. Acts like
    ## `true` or `false` in an `if`, and may carry results you can loop
    ## over.
    result*: T
    truthy*: bool

  World* = ref object of RootObj
    ## The world itself. There's exactly one, named `world`. Change its
    ## settings to change the scenery.

  PositionOffset* = object
    ## A position plus a distance, like `home + 5`. Move commands
    ## accept these as targets.
    position*: Vector3
    offset*: float
    direction*: Vector3

  Bot* = ref object of Thing
    ## A robot character. Bots can walk, run, play animations, and be
    ## programmed to do whatever you like.

  Build* = ref object of Thing
    ## Something made of blocks. Builds have a drawing turtle that
    ## commands like `forward` and `turn` steer around.

  Sign* = ref object of Thing
    ## A sign or message floating in the world.

  Player* = ref object of Thing
    ## A person playing the game. The one at this computer is named
    ## `player`.

  Color* = tuple[r, g, b, a: float32]
    ## A color value. The named colors (`blue`, `red`, ...) are instances of
    ## this type; environments will be able to remap them later. Any other
    ## value is a static color, unaffected by environment palettes.

  Colors* {.deprecated: "use Color".} = Color

  Context* = ref object
    stack*: seq[Frame]

  Frame* = ref object
    manager*: proc(active: bool): bool
    action*: proc()

  Halt* = object of CatchableError

  Loop* = ref object
    states*: Table[string, NimNode]
    from_states*: seq[(string, NimNode)]

  Tools* = enum
    ## Everything that can go in a player's toolbar: the code editor,
    ## one tool for each block color, and the bot placer.
    CodeMode
    BlueBlock
    RedBlock
    GreenBlock
    BlackBlock
    WhiteBlock
    BrownBlock
    PlaceBot
    None

proc `==`*(a, b: Color): bool =
  # Tolerant compare: VM const evaluation keeps float64 precision while
  # host round-trips are float32; the drift is ~1e-9, far below the 1/255
  # gap between distinct 8-bit color steps.
  abs(a.r - b.r) < 0.0001 and abs(a.g - b.g) < 0.0001 and
    abs(a.b - b.b) < 0.0001 and abs(a.a - b.a) < 0.0001

proc color_from_hex(hex: int): Color =
  (
    r: float32((hex shr 16) and 0xff) / 255,
    g: float32((hex shr 8) and 0xff) / 255,
    b: float32(hex and 0xff) / 255,
    a: 1.0'f32,
  )

const
  eraser*: Color = (0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32)
  blue* = color_from_hex(0x0067ff)
  red* = color_from_hex(0xfc0e0b)
  green* = color_from_hex(0x14f707)
  black* = color_from_hex(0x000000)
  white* = color_from_hex(0xd9eed8)
  brown* = color_from_hex(0x3f302b)
# Timing types - simple wrappers that don't require posix

type
  Timestamp* = object
    ## A point in time, measured in seconds since Enu started. Get one
    ## with `now()`.
    seconds_since_start: float

  Duration* = object
    ## An amount of time. Subtracting two timestamps gives you one.
    total_seconds: float

proc init*(_: type Timestamp, seconds: float): Timestamp =
  Timestamp(seconds_since_start: seconds)

proc init*(_: type Duration, seconds: float): Duration =
  Duration(total_seconds: seconds)

proc `-`*(a, b: Timestamp): Duration =
  ## Subtract timestamps to find out how much time passed between them.
  Duration(total_seconds: a.seconds_since_start - b.seconds_since_start)

proc `+`*(a: Timestamp, b: Duration): Timestamp =
  Timestamp(seconds_since_start: a.seconds_since_start + b.total_seconds)

proc `-`*(a: Timestamp, b: Duration): Timestamp =
  Timestamp(seconds_since_start: a.seconds_since_start - b.total_seconds)

proc `+`*(a, b: Duration): Duration =
  Duration(total_seconds: a.total_seconds + b.total_seconds)

proc `-`*(a, b: Duration): Duration =
  Duration(total_seconds: a.total_seconds - b.total_seconds)

proc seconds*(d: Duration): float =
  ## The duration as a number of seconds.
  d.total_seconds

proc milliseconds*(d: Duration): float =
  ## The duration as a number of milliseconds.
  d.total_seconds * 1000.0

proc `$`*(d: Duration): string =
  let s = d.total_seconds
  if s < 0.001:
    $(s * 1_000_000) & "us"
  elif s < 1.0:
    $(s * 1000) & "ms"
  else:
    $s & "s"

proc `$`*(t: Timestamp): string =
  $t.seconds_since_start & "s"

proc `<`*(a, b: Duration): bool =
  a.total_seconds < b.total_seconds

proc `<=`*(a, b: Duration): bool =
  a.total_seconds <= b.total_seconds

proc `>`*(a, b: Duration): bool =
  a.total_seconds > b.total_seconds

proc `>=`*(a, b: Duration): bool =
  a.total_seconds >= b.total_seconds

proc `==`*(a, b: Duration): bool =
  a.total_seconds == b.total_seconds

proc `<`*(a, b: Timestamp): bool =
  a.seconds_since_start < b.seconds_since_start

proc `>`*(a, b: Timestamp): bool =
  a.seconds_since_start > b.seconds_since_start
