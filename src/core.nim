import types
export types

import pkg/model_citizen/utils
import
  std/[
    sequtils, strutils, sugar, macros, asyncfutures, importutils, typetraits,
    posix,
  ]
export utils, sequtils, strutils, sugar, importutils

### Globals ###

const enu_version* = static_exec("git describe --tags HEAD")
var state* {.threadvar.}: GameState
var saved_state* {.threadvar.}: SavedState
const animation_duration* = 0.3

### Sugar ###

from sugar import dup, dump, collect
import std/[with, sets, tables]
import std/times except seconds
import pkg/[pretty, flatty]

export with, sets, tables, pretty, flatty

proc minutes*(m: float | int): Duration {.inline.} =
  init_duration(seconds = int(m * 60))

### Debug

export dump

import pkg/chronicles
export chronicles

template nim_filename*(): string =
  instantiation_info(full_paths = true).filename

### options ###

import options
export options

proc `||=`*[T](opt: var Option[T], val: T): T {.discardable.} =
  if not opt.is_some:
    opt = some(val)
    result = val
  else:
    result = opt.get()

proc `||`*[T](a: Option[T], b: T): T =
  if ?a: a.get else: b

proc `||=`*[T](a: var T, b: T) =
  if not ?a:
    a = b

converter from_option*[T](val: Option[T]): T =
  val.get()

proc optional_get*[T](self: var HashSet[T], key: T): Option[T] =
  if key in self:
    result = some(self[key])
  else:
    result = none(T)

### Vector3 ###

import gdext, math
export Transform3D, Vector3, Vector2, Basis, AABB, print, vector3, vector2

# String converters for Godot types
converter to_gd_string*(s: string): String =
  new_gd_string(s)

converter to_string_name*(s: string): StringName =
  new_string_name(s)

const
  UP* = vector3(0, 1, 0)
  DOWN* = vector3(0, -1, 0)
  BACK* = vector3(0, 0, 1)
  FORWARD* = vector3(0, 0, -1)
  RIGHT* = vector3(1, 0, 0)
  LEFT* = vector3(-1, 0, 0)

proc vector3(x, y, z: int): Vector3 {.inline.} =
  vector3(x.float, y.float, z.float)

proc trunc*(self: Vector3): Vector3 {.inline.} =
  vector3(trunc(self.x), trunc(self.y), trunc(self.z))

proc inverse_normalized*(self: Vector3): Vector3 {.inline.} =
  (self - vector3(self.length, self.length, self.length)) * -1

proc first*[T](arr: open_array[T], test: proc(x: T): bool): Option[T] =
  for item in arr:
    if test(item):
      return some(item)

proc round*(v: Vector3): Vector3 {.inline.} =
  vector3(v.x.round(), v.y.round(), v.z.round())

proc is_axis_aligned*(v: Vector3): bool {.inline.} =
  v in [UP, DOWN, LEFT, RIGHT, FORWARD, BACK]

proc limit_length*(self: Vector2, length: float): Vector2 =
  let l = self.length()
  result = self
  if l > 0 and length < l:
    result /= l
    result *= length

proc within*(
    self: Vector2, position: Vector2, size: Vector2, scale = vector2(1.0, 1.0)
): bool =
  let x = self.x >= position.x and self.x <= position.x + (size.x * scale.x)
  let y = self.y >= position.y and self.y <= position.y + (size.y * scale.y)
  result = x and y

# Basis

# Column accessor methods that extract axis vectors from row-stored data
# In gdext-nim, basis.x/y/z and basis[0/1/2] return rows, not columns
# These methods provide the expected axis vectors (columns)

proc get_column_x*(self: Basis): Vector3 {.inline.} =
  ## Returns the right vector (first column)
  vector3(self.x.x, self.y.x, self.z.x)

proc get_column_y*(self: Basis): Vector3 {.inline.} =
  ## Returns the up vector (second column)
  vector3(self.x.y, self.y.y, self.z.y)

proc get_column_z*(self: Basis): Vector3 {.inline.} =
  ## Returns the forward vector (third column, -Z in Godot's coordinate system)
  vector3(self.x.z, self.y.z, self.z.z)

proc surrounding*(point: Vector3): seq[Vector3] =
  collect(new_seq):
    for x in 0 .. 2:
      for y in 0 .. 2:
        for z in 0 .. 2:
          point + vector3(x - 1, y - 1, z - 1)

# math

const CMP_EPSILON = 0.00001
proc roughly_zero[T](s: T): bool =
  abs(s) < CMP_EPSILON

proc lerp*(self, other, t: float): float {.inline.} =
  self + t * (other - self)

proc wrap*[T](value, min, max: T): float =
  let range = max - min
  if range.roughly_zero:
    min
  else:
    value - (range * floor((value - min) / range))

# output

proc logger*(level, msg: string) =
  if not state.logger.is_nil:
    state.logger(level, msg)
  else:
    error "logger not initialized", level, msg

proc debug*(self: GameState, args: varargs[string, `$`]) =
  logger("debug", args.join)

proc info*(self: GameState, args: varargs[string, `$`]) =
  logger("info", args.join)

proc err*(self: GameState, args: varargs[string, `$`]) =
  logger("err", \"[color=#FF0000]{args.join}[/color]")

# when not defined(no_godot):
#   when default_chronicles_stream.outputs.tuple_len > 0:
#     default_chronicles_stream.outputs[0].writer = proc(
#         log_level: LogLevel, msg: LogOutputStr
#     ) {.gcsafe.} =
#       try:
#         # when defined(release):
#         # GD4: print msg - not GC-safe, need alternative approach
#         if log_level >= ERROR and not state.logger.is_nil:
#           state.err(msg)
#         # else:
#         #   if log_level >= INFO:
#         #     echo msg
#       except Exception as e:
#         error "Error in logging", error = e.msg

#   when default_chronicles_stream.outputs.tuple_len > 1:
#     discard default_chronicles_stream.outputs[1].open(
#       \"logs/enu-{times.now().format(\"yyyyMMdd-HHmmss\")}.log", fm_append
#     )

# misc

template breakpoint*() =
  {.line.}:
    discard `raise` SIGINT

proc resolve_level_name*(world, level: string, diff: int): string =
  var level = level
  let prefix = world & "-"
  level.remove_prefix(prefix)
  var og_num =
    try:
      level.parse_int
    except ValueError:
      1
  let num = og_num + diff
  result =
    if diff < 0 and num < 1:
      prefix & $og_num
    else:
      prefix & $num

proc init*(_: type Future, T: type, proc_name = ""): Future[T] =
  return new_future[T](proc_name)

#import pkg/core/transforms
#export transforms

#import pkg/godot

import pkg/model_citizen
export model_citizen

proc global_from*(self: Vector3, unit: Unit): Vector3 =
  result = self
  var unit = unit
  while unit != nil:
    result += unit.transform.origin
    unit = unit.parent

proc local_to*(self: Vector3, unit: Unit): Vector3 =
  result = self
  var unit = unit
  while unit != nil:
    result -= unit.transform.origin
    unit = unit.parent

proc `+=`*(self: ZenValue[string], str: string) =
  self.value = self.value & str

proc origin*(self: ZenValue[Transform3D]): Vector3 =
  self.value.origin

proc `origin=`*(self: ZenValue[Transform3D], value: Vector3) =
  var transform = self.value
  transform.origin = value
  self.value = transform

proc basis*(self: ZenValue[Transform3D]): Basis =
  self.value.basis

proc `basis=`*(self: ZenValue[Transform3D], value: Basis) =
  var transform = self.value
  transform.basis = value
  self.value = transform

proc init*(_: type Basis): Basis =
  basis()

proc init*(_: type Transform3D, origin = vector3()): Transform3D =
  Transform3D(basis: basis(), origin: origin)

proc init*(_: type Code, nim: string): Code =
  Code(owner: state.worker_ctx_name, nim: nim)

proc update_action_index*(state: GameState, change: int) =
  var index = int(state.current_tool) + change
  if index < 0:
    index = int Tools.high
  elif index > int Tools.high:
    index = int Tools.low

  state.current_tool = Tools(index)

template watch*[T, O](zen: Zen[T, O], unit: untyped, body: untyped) =
  when unit is Unit:
    mixin thread_ctx
    let zid = zen.changes:
      body
    unit.zids.add(zid)
    make_discardable(zid)
  else:
    {.
      error:
        "Watch needs a Unit object to bind its lifetime to. The Unit " &
        "can be passed explicitly, or found implicitly by evaluating " &
        "`self.model`, then `self`."
    .}

template watch*[T, O](zen: Zen[T, O], body: untyped) =
  when compiles(self.model):
    watch(zen, self.model, body)
  else:
    watch(zen, self, body)

# from https://forum.nim-lang.org/t/5481#34239
macro enum_fields*(n: typed): untyped =
  let impl = get_type(n)
  expect_kind impl[1], nnk_enum_ty
  result = nnk_bracket.new_tree()
  for f in impl[1]:
    case f.kind
    of nnk_sym, nnk_ident:
      result.add new_lit(f.str_val)
    else:
      discard

template value*(self: ZenValue, body: untyped) {.dirty.} =
  block:
    var value = self.value
    with value:
      body
    self.value = value

var deferred {.threadvar.}: seq[proc() {.closure, gcsafe.}]
template after_boop*(body: untyped) =
  deferred.add proc() =
    body

proc run_deferred*() =
  for fn in deferred:
    fn()
  deferred.set_len(0)

const environments* = {
  "default": 0.0,
  "blue": 0.0,
  "bright": 0.0,
  "bw": 0.0,
  "bw2": 0.0,
  "bw3": 0.0,
  "noir": 0.0,
  "dream": 0.0,
  "opposite": 0.0,
  "none": 0.0,
  "arcade": 0.1,
  "gb": 0.02,
  "gb2": 0.02,
  "strange": 0.5,
  "wild_imagination": 0.3,
}.to_table

template `?=`*[T](a: var T, b: T) =
  if not ?a:
    a = b

template `?`*[T](self: seq[T]): bool =
  self.len > 0

template `?`*(self: Table): bool =
  self.len > 0

template `?`*(self: tuple): bool =
  self != self.type.default

template `?`*(self: bool): bool =
  self

template `?`*[T](gdref: GdRef[T]): bool =
  not gdref.handle.is_nil()

template `?`*(obj: ptr): bool =
  not obj.is_nil()

template `?`*[T: proc](p: T): bool =
  not p.is_nil()

proc first_key*[K, V](self: Table[K, V]): K =
  for key in self.keys:
    return key
