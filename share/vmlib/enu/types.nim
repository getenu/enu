import std/[tables, random, macros]

var global_default* = false

const yes* = true
const no* = false
const ASAP* = 0.0
  ## Magic speed value. `speed = ASAP` makes a build draw everything at
  ## once instead of block by block.

type
  Vector3* = tuple[x, y, z: float]
    ## A spot (or a direction) in the world. `x` is left/right, `y` is
    ## up/down, and `z` is forward/back.

  WorldBox* = tuple[min, max: Vector3]
    ## An invisible box around a unit, described by its lowest corner
    ## and its highest corner. Used to check what fits where.

  Directions* = enum
    ## The 6 directions a unit can move, turn or lean. Each one has a
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

  Unit* = ref object of RootObj
    ## Anything that exists in the world — a build, a bot, a sign, or
    ## the player. Most commands work on any unit.
    id: int
    name*: string
    advance_state_machine*: proc(): bool
    rng: Rand
    seed: int
    sign*: Sign
    query_results*: Table[string, seq[Unit]]

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

  Bot* = ref object of Unit
    ## A robot character. Bots can walk, run, play animations, and be
    ## programmed to do whatever you like.

  Build* = ref object of Unit
    ## Something made of blocks. Builds have a drawing turtle that
    ## commands like `forward` and `turn` steer around.

  Sign* = ref object of Unit
    ## A sign or message floating in the world.

  Player* = ref object of Unit
    ## A person playing the game. The one at this computer is named
    ## `player`.

  Colors* = enum
    ## The colors blocks come in. `eraser` isn't really a color — it
    ## removes blocks instead of drawing them.
    eraser
    blue
    red
    green
    black
    white
    brown

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
