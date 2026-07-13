## The heart of the Enu API: moving, turning, building, random numbers,
## timers, and the other everyday commands that every script can use.

import system except echo
import
  std/[
    strformat, math, importutils, strutils, options, sets, sequtils, algorithm
  ]
import random as rnd except rand
import types, vectors, base_bridge, base_bridge_private

export types, vectors, base_bridge
export strutils

proc init*[T: Exception](
    kind: type[T], message: string, parent: ref Exception = nil
): ref Exception =
  ## Make an error you can `raise`. For example,
  ## `raise ValueError.init("that's not going to work")`.
  (ref kind)(msg: message, parent: parent)

proc now*(): Timestamp =
  ## The time right now. Subtract two of these to see how much time
  ## passed:
  ##   let start = now()
  ##   # ... do something slow ...
  ##   echo "Took ", now() - start
  Timestamp.init(now_seconds())

var state_init_callbacks: seq[proc()] = @[]

proc register_state_init*(callback: proc()) =
  ## Used by Enu while a level loads. You won't need this in a script.
  state_init_callbacks.add(callback)

proc initialize_state*() =
  ## Used by Enu while a level loads. You won't need this in a script.
  for callback in state_init_callbacks:
    callback()

proc echo*(args: varargs[string, `$`]) =
  ## Print something to the console. The best way to spy on what your
  ## script is up to: `echo "score is ", score`.
  echo_console(args.join)

proc quit*(code = 0, msg = "") =
  ## Stop the script.
  exit(code, msg)

proc `position=`*(self: Thing, position: Vector3) =
  ## Teleport the thing. No walking, no animation, it's just there now.
  ## You can also assign another thing to teleport to wherever it is:
  ## `me.position = player.position`, or just `me.position = player`.
  self.position_set(position)

proc apply_position*(self: Thing, position: Vector3) =
  ## Teleport the thing, unless the position is unset. Used by Enu
  ## internally.
  if position.x != float.high:
    self.position = position

proc `position=`*(self: Thing, thing: Thing) =
  self.position_set(thing.position)

proc `start_position=`*(self: Thing, position: Vector3) =
  ## Change where the thing starts. Unlike `position=`, this is
  ## remembered when the level reloads.
  self.start_position_set(position)

proc delete*(self: Thing) =
  ## Remove the thing from the level, along with its script and saved
  ## data. There's no undo, so be really sure.
  base_bridge_private.delete(self)

proc keep_alive*() =
  ## Enu stops scripts that grind away for ~2 seconds without pausing,
  ## in case they're stuck. If your loop really does need that long,
  ## call this now and then to say "not stuck, just busy!"
  base_bridge_private.keep_alive()

proc go*(self: Thing, position: Thing | Vector3) =
  ## Teleport the thing to a position, or to another thing. The same as
  ## setting `position=`.
  self.position = position

proc `seed=`*(self: Thing, seed: int) =
  ## Random numbers in Enu follow a secret recipe called a seed. Give
  ## two things the same seed and they'll roll the same "random" numbers
  ## in the same order. By default every thing gets a different seed.
  private_access Thing
  self.rng = init_rand(seed)
  self.seed = seed

proc seed*(self: Thing): int =
  ## The thing's random seed. See `seed=`.
  private_access Thing
  self.seed

proc bounce*(me: Player, power = 1.0) =
  ## Launch the player into the air. More power, more air.
  me.velocity = me.velocity + UP * power * 30

template wait(body: untyped) =
  mixin action_running, `action_running=`, yield_script
  let self = active_thing()
  `action_running=`(self, true)
  body
  while self.action_running and self.advance_state_machine():
    self.yield_script()

proc sleep*(seconds = -1.0) =
  ## Do nothing for this many seconds. With no argument, naps for up to
  ## half a second but wakes up early if something bumps into the thing —
  ## perfect for a loop that mostly waits around. `sleep 0` yields a
  ## single tick (hand control back to the engine for one frame, then
  ## carry on).
  wait sleep_impl(seconds)

proc forward*(self: Thing, steps: float, move_mode: int) =
  ## Go forward this many blocks (1 if you don't say). In `build` mode
  ## the turtle draws blocks as it goes; in `move` mode the whole thing
  ## moves. You can also pass a spot like `home`: `forward home` goes
  ## forward until you're even with it, and `forward home + 2` goes 2
  ## blocks past.
  wait self.begin_move(FORWARD, steps, move_mode)

template forward*(self: Thing, steps = 1.0) =
  mixin wait, begin_move
  wait self.begin_move(FORWARD, steps, move_mode)

proc back*(self: Thing, steps: float, move_mode: int) =
  ## Like `forward`, but backward.
  wait self.begin_move(BACK, steps, move_mode)

template back*(self: Thing, steps = 1.0) =
  mixin wait, begin_move
  wait self.begin_move(BACK, steps, move_mode)

proc left*(self: Thing, steps: float, move_mode: int) =
  ## Go left this many blocks (1 if you don't say). Slides sideways,
  ## no turning.
  wait self.begin_move(LEFT, steps, move_mode)

template left*(self: Thing, steps = 1.0) =
  mixin wait, begin_move
  wait self.begin_move(LEFT, steps, move_mode)

proc right*(self: Thing, steps: float, move_mode: int) =
  ## Go right this many blocks (1 if you don't say). Slides sideways,
  ## no turning.
  wait self.begin_move(RIGHT, steps, move_mode)

template right*(self: Thing, steps = 1.0) =
  mixin wait, begin_move
  wait self.begin_move(RIGHT, steps, move_mode)

proc up*(self: Thing, steps: float, move_mode: int) =
  ## Go up this many blocks (1 if you don't say).
  wait self.begin_move(UP, steps, move_mode)

template up*(self: Thing, steps = 1.0) =
  mixin wait, begin_move
  wait self.begin_move(UP, steps, move_mode)

proc down*(self: Thing, steps: float, move_mode: int) =
  ## Go down this many blocks (1 if you don't say).
  wait self.begin_move(DOWN, steps, move_mode)

template down*(self: Thing, steps = 1.0) =
  mixin wait, begin_move
  wait self.begin_move(DOWN, steps, move_mode)

template l*(self: Thing, steps = 1.0) =
  ## Shorthand for `left`.
  self.left(steps)

template r*(self: Thing, steps = 1.0) =
  ## Shorthand for `right`.
  self.right(steps)

template u*(self: Thing, steps = 1.0) =
  ## Shorthand for `up`.
  self.up(steps)

template d*(self: Thing, steps = 1.0) =
  ## Shorthand for `down`.
  self.down(steps)

template f*(self: Thing, steps = 1.0) =
  ## Shorthand for `forward`.
  self.forward(steps)

template b*(self: Thing, steps = 1.0) =
  ## Shorthand for `back`.
  self.back(steps)

template forward*(steps = 1.0) =
  ## Go forward this many blocks (1 if you don't say). In `build` mode
  ## the turtle draws blocks as it goes; in `move` mode the whole thing
  ## moves. `f` is the short version.
  enu_target.forward(steps)

template back*(steps = 1.0) =
  ## Like `forward`, but backward. `b` for short.
  enu_target.back(steps)

template left*(steps = 1.0) =
  ## Go left this many blocks (1 if you don't say). Slides sideways,
  ## no turning. `l` for short.
  enu_target.left(steps)

template right*(steps = 1.0) =
  ## Go right this many blocks (1 if you don't say). Slides sideways,
  ## no turning. `r` for short.
  enu_target.right(steps)

template up*(steps = 1.0) =
  ## Go up this many blocks (1 if you don't say). `u` for short.
  enu_target.up(steps)

template down*(steps = 1.0) =
  ## Go down this many blocks (1 if you don't say). `d` for short.
  enu_target.down(steps)

template l*(steps = 1.0) =
  ## Shorthand for `left`.
  enu_target.left(steps)

template r*(steps = 1.0) =
  ## Shorthand for `right`.
  enu_target.right(steps)

template u*(steps = 1.0) =
  ## Shorthand for `up`.
  enu_target.up(steps)

template d*(steps = 1.0) =
  ## Shorthand for `down`.
  enu_target.down(steps)

template f*(steps = 1.0) =
  ## Shorthand for `forward`.
  enu_target.forward(steps)

template b*(steps = 1.0) =
  ## Shorthand for `back`.
  enu_target.back(steps)

template see*(target: Thing, less_than = 100.0): bool =
  ## `true` if this thing can see the target: nothing solid in the way,
  ## and it's closer than `less_than` (100 blocks unless you say
  ## otherwise). `sees` works too, so `if me.sees player:` reads nicely.
  enu_target.see(target, less_than)

template sees*(target: Thing, less_than = 100.0): bool =
  ## Alias of `see`.
  enu_target.see(target, less_than)

proc sees*(self: Thing, target: Thing, less_than = 100.0): bool =
  sees_impl(self, target, less_than)

proc see*(self: Thing, target: Thing, less_than = 100.0): bool =
  sees(self, target, less_than)

proc forward*(self: Thing, value: PositionOffset, move_mode: int) =
  let steps = self.local_position.z - value.position.z + value.offset
  wait self.begin_move(FORWARD, steps, move_mode)

template forward*(self: Thing, value: PositionOffset) =
  mixin wait, begin_move
  let steps = self.local_position.z - value.position.z + value.offset
  wait self.begin_move(FORWARD, steps, move_mode)

template forward*(offset: PositionOffset) =
  enu_target.forward(offset)

proc back*(self: Thing, value: PositionOffset, move_mode: int) =
  let steps = self.position.z - value.position.z - value.offset
  wait self.begin_move(FORWARD, steps, move_mode)

template back*(self: Thing, value: PositionOffset) =
  mixin wait, begin_move
  let steps = self.local_position.z - value.position.z - value.offset
  wait self.begin_move(FORWARD, steps, move_mode)

template back*(offset: PositionOffset) =
  enu_target.back(offset)

proc left*(self: Thing, value: PositionOffset, move_mode: int) =
  let steps = self.local_position.x - value.position.x + value.offset
  wait self.begin_move(LEFT, steps, move_mode)

template left*(self: Thing, value: PositionOffset) =
  mixin wait, begin_move
  let steps = self.local_position.x - value.position.x + value.offset
  wait self.begin_move(LEFT, steps, move_mode)

template left*(offset: PositionOffset) =
  enu_target.left(offset)

proc right*(self: Thing, value: PositionOffset, move_mode: int) =
  let steps = self.local_position.x - value.position.x - value.offset
  wait self.begin_move(LEFT, steps, move_mode)

template right*(self: Thing, value: PositionOffset) =
  mixin wait, begin_move
  let steps = self.local_position.x - value.position.x - value.offset
  wait self.begin_move(LEFT, steps, move_mode)

template right*(offset: PositionOffset) =
  enu_target.right(offset)

proc down*(self: Thing, value: PositionOffset, move_mode: int) =
  let steps = self.local_position.y - value.position.y + value.offset
  wait self.begin_move(DOWN, steps, move_mode)

template down*(self: Thing, value: PositionOffset) =
  mixin wait, begin_move
  let steps = self.local_position.y - value.position.y + value.offset
  wait self.begin_move(DOWN, steps, move_mode)

template down*(offset: PositionOffset) =
  enu_target.down(offset)

proc up*(self: Thing, value: PositionOffset, move_mode: int) =
  let steps = self.local_position.y - value.position.y - value.offset
  wait self.begin_move(DOWN, steps, move_mode)

template up*(self: Thing, value: PositionOffset) =
  mixin wait, begin_move
  let steps = self.local_position.y - value.position.y - value.offset
  wait self.begin_move(DOWN, steps, move_mode)

template up*(offset: PositionOffset) =
  enu_target.up(offset)

type NegativeNode = ref object
  node: Thing

proc `-`*(node: Thing): NegativeNode =
  ## A minus sign in front of a thing means "away from it".
  ## `turn -player` turns your back on the player. Rude, but allowed.
  NegativeNode(node: node)

proc angle_to*(self: Thing, position: Vector3): float =
  ## How many degrees this thing would have to turn to face a position
  ## (or another thing).
  let
    p1 = self.position
    d = (p1 - position).normalized()
  let n = arctan2(d.x, d.z).rad_to_deg
  let rot = self.rotation
  result = -(n - rot)

proc angle_to*(self: Thing, enu_target: Thing): float =
  self.angle_to(enu_target.position)

proc vec3(direction: Directions): Vector3 =
  result =
    case direction
    of Directions.forward, Directions.f: FORWARD
    of Directions.back, Directions.b: BACK
    of Directions.left, Directions.l: LEFT
    of Directions.right, Directions.r: RIGHT
    of Directions.up, Directions.u: UP
    of Directions.down, Directions.d: DOWN

proc turn*(self: Thing, direction: Directions, degrees = 90.0, move_mode: int) =
  ## Turn the thing (or the drawing turtle). You can turn:
  ## - a direction: `turn left`, or `turn left, 45` for 45 degrees
  ## - a number of degrees: `turn 90` (positive turns right,
  ##   negative turns left)
  ## - toward something: `turn player`
  ## - away from something: `turn -player`
  ## `t` is the short version.
  let dir = vec3(direction)
  if dir in [BACK, FORWARD]:
    raise IndexDefect.init("You can't turn forward or back")

  self.begin_turn(dir, degrees, false, move_mode)

proc turn*(self: Thing, degrees: float, move_mode: int) =
  let degrees = floor_mod(degrees, 360)
  if degrees <= 180:
    self.turn Directions.right, degrees, move_mode
  else:
    let d = 180 - (degrees - 180)
    self.turn Directions.left, 180 - (degrees - 180), move_mode

template turn*(self: Thing, direction: Directions, degrees = 90.0) =
  mixin wait
  wait turn(self, direction, degrees, move_mode)

template turn*(direction: Directions, degrees = 90.0) =
  ## Turn the thing (or the drawing turtle). You can turn:
  ## - a direction: `turn left`, or `turn left, 45` for 45 degrees
  ## - a number of degrees: `turn 90` (positive turns right,
  ##   negative turns left)
  ## - toward something: `turn player`
  ## - away from something: `turn -player`
  ## `t` is the short version.
  mixin wait
  wait enu_target.turn(direction, degrees, move_mode)

template t*(direction: Directions, degrees = 90.0) =
  ## Shorthand for `turn`.
  turn direction, degrees

template turn*(degrees: float) =
  mixin wait
  wait enu_target.turn(degrees, move_mode)

template t*(degrees: float) =
  turn degrees

template turn*(self: Thing, degrees: float) =
  mixin wait
  wait self.turn(degrees, move_mode)

template t*(self: Thing, degrees: float) =
  turn self, degrees

proc lean*(self: Thing, direction: Directions, degrees = 90.0, move_mode: int) =
  ## Tip the thing (or the drawing turtle) forward, back, left or
  ## right. Like `turn`, but instead of spinning like a top, you tilt,
  ## which lets the turtle draw up and down walls or loop-the-loops.
  let dir = vec3(direction)
  if dir in [UP, DOWN]:
    raise IndexDefect.init("You can't lean up or down")

  self.begin_turn(dir, degrees, true, move_mode)

proc lean*(self: Thing, degrees: float, move_mode: int) =
  let degrees = floor_mod(degrees, 360)
  if degrees <= 180:
    self.lean Directions.right, degrees, move_mode
  else:
    self.lean Directions.left, 180 - (degrees - 180), move_mode

template lean*(self: Thing, direction: Directions, degrees = 90.0) =
  mixin wait
  wait lean(self, direction, degrees, move_mode)

template lean*(direction: Directions, degrees = 90.0) =
  ## Tip the thing (or the drawing turtle) forward, back, left or
  ## right. Like `turn`, but instead of spinning like a top, you tilt,
  ## which lets the turtle draw up and down walls or loop-the-loops.
  mixin wait
  wait enu_target.lean(direction, degrees, move_mode)

template lean*(degrees: float) =
  mixin wait
  wait enu_target.lean(degrees, move_mode)

template lean*(self: Thing, degrees: float) =
  mixin wait
  wait self.lean(degrees, move_mode)

template move*[T: Thing](new_enu_target: T) =
  ## Switch to move mode: commands like `forward` and `turn` now move
  ## the thing around instead of drawing blocks. `move me` moves this
  ## thing; `move enemy` steers a different one. (If the speed was 0,
  ## it's bumped to 1 so you can actually see something happen.)
  when enu_target is Build:
    enu_target.end_asap()
  enu_target = new_enu_target
  move_mode = 2
  if enu_target.speed == 0:
    enu_target.speed = 1

template build*(new_enu_target: Thing) =
  ## Switch to build mode: commands like `forward` and `turn` steer
  ## the drawing turtle, leaving a trail of blocks. This is the normal
  ## mode for a Build, so you mostly need it to switch back after
  ## `move`, or to aim commands at a different thing: `build enemy`.
  when enu_target is Build:
    enu_target.end_asap()
  enu_target = new_enu_target
  move_mode = 1

template anchor*(body: untyped) =
  ## Declare the thing's pivot. Inside the block, turtle commands
  ## (`forward`, `right`, `up`, `turn`, `lean`, …) accumulate into the
  ## thing's anchor pose instead of drawing voxels or moving the thing.
  ## The turtle starts at the proto's local `(0, 0, 0)` facing -Z.
  ##
  ## After the block, `position` places the anchor pivot at the given
  ## world coord, `rotation` pivots around it, and `move me; forward`
  ## moves along the anchor's intrinsic forward.
  mixin reset_anchor
  enu_target.reset_anchor()
  let saved_move_mode = move_mode
  move_mode = 3
  body
  move_mode = saved_move_mode

template anchor*(target: Thing, body: untyped) =
  ## Re-anchor an existing instance. Visibly moves/reorients the
  ## instance because it's already rendered; the thing's `position` and
  ## `rotation` stay constant from the user's perspective.
  mixin reset_anchor
  let saved_enu_target = enu_target
  let saved_move_mode = move_mode
  enu_target = target
  enu_target.reset_anchor()
  move_mode = 3
  body
  enu_target = saved_enu_target
  move_mode = saved_move_mode

proc turn*(self: Thing, position: Vector3, move_mode: int) =
  self.turn(self.angle_to(position), move_mode)

template turn*(self: Thing, position: Vector3) =
  self.turn(position, move_mode)

template turn*(position: Vector3) =
  active_thing().turn(position)

template t*(position: Vector3) =
  turn position

proc turn*(self: Thing, enu_target: Thing, move_mode: int) =
  self.turn(self.angle_to(enu_target), move_mode)

template turn*(self: Thing, enu_target: Thing) =
  self.turn(enu_target, move_mode)

template turn*(enu_target: Thing) =
  active_thing().turn(enu_target)

template t*(enu_target: Thing) =
  turn enu_target

template turn*(self: Thing, enu_target: NegativeNode) =
  self.turn(self.angle_to(enu_target.node) - 180, move_mode)

template turn*(enu_target: NegativeNode) =
  active_thing().turn(enu_target)

template t*(enu_target: NegativeNode) =
  turn(enu_target)

proc distance*(position: Vector3): float =
  ## How far away something is from this thing, in blocks.
  ## `player.distance` or `distance vec3(10, 0, 10)`.
  position.distance_to(active_thing().position)

proc distance*(node: Thing): float =
  node.position.distance

proc find_by_id*(id: string): Thing =
  ## Search every thing in the world for the one with this id. Returns
  ## `nil` if there's no such thing.
  for u in all_things():
    if u.id == id:
      return u

proc things_near*(x, y, z: float, radius = 30.0): string =
  ## Lists every Thing in the world whose xz-distance to (x, y, z) is <=
  ## radius, sorted nearest-first. One line per thing, formatted as:
  ##   d=DD.D  thing_id  (X, Y, Z)
  ## Useful when chasing overlap reports / "# CLAUDE: ..." marker blocks
  ## from MCP: pass the marker's position and skim the candidates.
  var rows: seq[(float, string)] = @[]
  for u in all_things():
    if u.is_nil: continue
    let p = u.position
    let dx = p.x - x
    let dz = p.z - z
    let d = sqrt(dx * dx + dz * dz)
    if d <= radius:
      rows.add(
        (d, &"d={d:5.1f}  {u.id:30s} ({p.x:6.1f}, {p.y:4.1f}, {p.z:6.1f})")
      )
  rows.sort(proc(a, b: (float, string)): int = cmp(a[0], b[0]))
  var lines: seq[string] = @[]
  for r in rows:
    lines.add(r[1])
  lines.join("\n")

proc near*(node: Thing | Vector3, less_than = 5.0): bool =
  ## `true` if something is closer than `less_than` blocks (5 unless
  ## you say otherwise). `if player.near:` or `if player.near(20):`.
  result = node.distance < less_than

proc far*(node: Thing | Vector3, greater_than = 100.0): bool =
  ## `true` if something is farther than `greater_than` blocks
  ## (100 unless you say otherwise).
  result = node.distance > greater_than

proc over*(node: Thing): bool =
  result = active_thing().position.z > node.position.z

proc under*(node: Thing): bool =
  result = active_thing().position.z < node.position.z

proc height*(self: Vector3): float =
  ## How high up something is. The same as `position.y`.
  self.y

proc height*(self: Thing): float =
  self.position.y

template go_home*() =
  ## Head back to the start position by going forward, left, and down
  ## the right amounts. Something solid can block the trip, so if it
  ## really matters, compare `position` to `start_position` afterward
  ## to check you made it.
  enu_target.go_home

import macros, tables
export tables

proc rng(): var Rand =
  private_access Thing
  var thing = active_thing()
  if thing.seed == 0:
    randomize()
    thing.seed = rnd.rand(int.high)
    thing.rng = init_rand(thing.seed)
  thing.rng

proc rand*[T: int | float](range: Slice[T]): T =
  ## A random number from a range: `rand(1..6)` rolls a die. Mostly
  ## you don't even need to call this, passing a range where a number
  ## goes does it automatically, like `forward 2..10`.
  rnd.rand rng(),
    if range.a > range.b:
      range.b .. range.a
    else:
      range

converter int_to_float*(i: int): float =
  result = i.float

converter int_slice_to_float*(range: Slice[int]): float =
  rand(range).float

converter int_slice_to_fint*(range: Slice[int]): int =
  rand(range)

converter float_slice_to_float*(range: Slice[float]): float =
  rand(range)

proc fuzzed*(self, range: float): float =
  ## A copy of a number or position, nudged by a random amount up to
  ## `range`. `position.fuzzed(0.5)` is great for jitters, shivers and
  ## nervous-looking bots.
  result =
    if range > 0:
      self + (rand(0.0 .. range) - (range / 2.0))
    else:
      self

proc fuzzed*(self, range: Vector3): Vector3 =
  vec3(self.x.fuzzed(range.x), self.y.fuzzed(range.y), self.z.fuzzed(range.z))

proc fuzzed*(self: Vector3, range: float): Vector3 =
  self.fuzzed(vec3(range, range, range))

proc fuzzed*(self: Vector3, x, y, z: float): Vector3 =
  self.fuzzed(vec3(x, y, z))

template times*(count: int, body: untyped): untyped =
  ## Do something over and over. `4.times: forward 5; turn right`
  ## draws a square. Inside the block, `first` and `last` tell you if
  ## this is the first or last time through. Want a counter? Ask for
  ## one: `8.times(side):` counts `side` up from 0 to 7.
  for x in 0 ..< count:
    let first {.inject.} = (x == 0)
    let last {.inject.} = (x == count - 1)
    body

template times*(count: int, name: untyped, body: untyped): untyped =
  for name {.inject.} in 0 ..< count:
    let first {.inject.} = (name == 0)
    let last {.inject.} = (name == count - 1)
    body

template x*(count: int, body: untyped): untyped =
  ## Shorthand for `times`. `5.x: forward 2`.
  times(count, body)

macro dump*(x: typed): untyped =
  ## Print an expression and its value. `dump score` prints
  ## `score = 10`. Saves you typing the name twice while debugging.
  let s = x.toStrLit
  let r = quote:
    echo(`s` & " = " & $`x`)
  return r

template cycle*[T](args: varargs[T]): T =
  ## Each time it's called, hand back the next value in the list,
  ## looping around forever: red, green, blue, red, green, blue...
  ## `color = cycle(red, green, blue)`.
  var
    positions {.global.}: Table[(string, int, int), int]
    key = instantiation_info()

  inc positions.mget_or_put(key, -1)

  if positions[key] >= args.len:
    positions[key] = 0

  args[positions[key]]

proc random*[T](args: varargs[T]): T =
  ## Pick one of the choices at random.
  ## `color = random(red, green, blue)`.
  let i = rnd.rand(rng(), 0 .. (args.len - 1))
  args[i]

proc contains*(max, chance: int): bool =
  ## Roll the dice: `1 in 10` is true 1 time out of 10. Use it for
  ## things that should only happen sometimes:
  ## `if 1 in 100: echo "jackpot!"`.
  var r = rnd.rand(rng(), 1 .. max)
  result = r <= chance

template forever*(body) =
  ## Do something forever. The same as `while true`, but friendlier.
  ## `o` is the short version (it looks like a loop, see?).
  while true:
    body

template o*(body) =
  ## Shorthand for `forever`.
  while true:
    body

proc `+`*(self: PositionOffset, offset: float): PositionOffset =
  ## Add or subtract extra distance from a spot like `home`.
  ## `forward home + 2` stops 2 blocks past home.
  result = self
  result.offset += offset

proc `-`*(self: PositionOffset, offset: float): PositionOffset =
  result = self
  result.offset -= offset

proc go*(thing: Thing) =
  ## Travel to another thing: turn to face it, head forward until you
  ## arrive, then drop down to its height.
  # save position and height in case thing moves
  var position = thing.position
  var height = thing.height
  active_thing().turn(thing, 2)
  active_thing().forward((position - active_thing().position).length, 2)
  active_thing().down(active_thing().height - height, 2)

proc even*(self: int): bool =
  ## `true` for even numbers. `if frame.even:` does something every
  ## other time.
  self mod 2 == 0

proc odd*(self: int): bool =
  ## `true` for odd numbers.
  not self.even

template `\`*(s: string): string =
  ## Put values inside text: `\"score: {score}"` becomes
  ## `"score: 10"`. Anything in curly braces gets filled in.
  var f = fmt(s)
  f.remove_prefix("\n")
  f.remove_suffix(' ')
  f.remove_suffix("\n\n")
  f

proc init*[T](_: type Query, results: open_array[T]): Query[seq[T]] =
  result.result = results.to_seq
  result.truthy = results.len > 0

template `?`*[T: ref](self: T): Query[T] =
  ## "Is this something?" `?player.open_sign` is `true` if the player
  ## has a sign open, `false` if there's nothing there. Works on most
  ## things: empty text, empty lists and zero all count as "nothing".
  Query[T](truthy: not self.is_nil)

template `?`*[T: object](self: T): Query[T] =
  Query[T](truthy: self != self.type.default)

template `?`*[T](option: Option[T]): Query[T] =
  if option.is_some:
    Query[T](truthy: true)
  else:
    Query[T]()

template `?`*[T: SomeNumber](self: SomeNumber): Query[T] =
  Query[T](truthy: self != 0)

template `?`*(self: string): Query[string] =
  Query[string](truthy: self != "")

template `?`*[T: open_array](self: T): Query[T] =
  Query[T](truthy: self.len > 0)

template `?`*[T: Table](self: T): Query[T] =
  Query[T](truthy: self.len > 0)

template `?`*[T: set](self: T): Query[T] =
  Query[T](truthy: self.card > 0)

template `?`*[T: HashSet](self: T): Query[T] =
  Query[T](truthy: self.card > 0)

converter to_bool*(src: Query): bool =
  src.truthy

proc `or`*[T: not bool](a, b: T): T =
  ## Pick the first value that's "something". `name or "mystery guest"`
  ## gives you `name`, unless it's empty.
  if ?a:
    result = a
  else:
    result = b

proc first_key*[K, V](self: Table[K, V]): K =
  for key in self.keys:
    return key

template reset*(clear = false) =
  ## Send the thing back to its start position, rotation and scale.
  ## With `clear = true`, a Build also forgets its drawn blocks.
  enu_target.reset(clear)

proc loop_finished*() =
  ## Called by Enu at the end of each trip through a command loop.
  ## You won't need this in a script.
  let thing = active_thing()
  if ?thing.query_results:
    let key = thing.query_results.first_key
    let res = thing.query_results[key].pop
    if not ?thing.query_results[key]:
      thing.query_results.del key
      if not ?thing.query_results:
        sleep()
  else:
    sleep()

template query(T: type Thing, key: string, body: untyped): untyped =
  var result: T
  let thing = active_thing()
  if key in thing.query_results:
    result = T(thing.query_results[key][^1])
  else:
    let results = body
    if ?results:
      result = results[^1]
      thing.query_results[key] = results.map_it(Thing(it))
  result

iterator items*[T](self: Query[seq[T]]): T =
  for item in self.result:
    yield item

proc all*(_: type Bot): Query[seq[Bot]] =
  ## Every thing of a kind in the world: `Bot.all`, `Build.all`,
  ## `Player.all`, `Sign.all` or `Thing.all`. Loop over them with
  ## `for bot in Bot.all:`.
  Query.init all_bots()

proc all*(T: type Build): Query[seq[Build]] =
  Query.init all_builds()

proc all*(_: type Sign): Query[seq[Sign]] =
  Query.init all_signs()

proc all*(_: type Player): Query[seq[Player]] =
  Query.init all_players()

proc all*(_: type Thing): Query[seq[Thing]] =
  Query.init all_things()

proc len*[T: Thing](self: Query[seq[T]]): int =
  self.result.len

proc `[]`*[T: Thing](self: Query[seq[T]], index: int): T =
  self.result[index]

proc first*[T: Thing](_: type T): T =
  ## The first thing of a kind: `Player.first` is the first player,
  ## `Bot.first` the first bot. `nil` if there aren't any.
  for player in T.all.result:
    return player

proc added*(_: type Player): Query[seq[Player]] =
  ## Players who joined since the last time you asked. Useful in a
  ## loop to greet newcomers.
  Query.init added_things().filter_it(it of Player).map_it(Player(it))

proc hit*(_: type Player): Query[seq[Player]] =
  ## The players currently touching this thing, if any.
  ## `if Player.hit as toucher:` grabs one to work with.
  let rr = active_thing().current_colliders("Player").map_it(Player(it))
  result = Query.init rr

proc hit*(thing: Thing): bool =
  ## `true` if this thing is touching another thing. `if player.hit:`.
  active_thing().hit(thing)

proc `in`*(thing: Thing): bool =
  thing.hit(active_thing())

proc register_type[T: Thing](thing: T) =
  register_template_node(thing, $T)

template `as`*[T](q: Query[seq[T]], name: untyped): bool =
  ## Grab a result from a query and give it a name, right inside an
  ## `if`: `if Player.hit as toucher: toucher.bounce`. Only works
  ## inside a command loop.
  if loop_context.is_nil:
    raise
      ObjectConversionDefect.init("`as` can only be used inside an action loop")
  let key = $T & "-" & $instantiation_info()
  var result = false
  let name {.inject.}: T =
    if q.truthy:
      result = true
      T.query(key, q.result)
    else:
      T.default
  result

register_type Player()
register_type Bot()
register_type Build()
register_type Sign()
