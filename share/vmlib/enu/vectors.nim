import std/math
import types

proc vec3*(x, y, z: float): Vector3 {.inline.} =
  ## Make a `Vector3` — a spot (or a direction) in the world.
  ## `x` is left/right, `y` is up/down, and `z` is forward/back.
  (x: x, y: y, z: z)

const
  UP* = vec3(0, 1, 0)
  DOWN* = vec3(0, -1, 0)
  BACK* = vec3(0, 0, 1)
  FORWARD* = vec3(0, 0, -1)
  RIGHT* = vec3(1, 0, 0)
  LEFT* = vec3(-1, 0, 0)
  UNSET_POSITION* = vec3(float.high, float.high, float.high)

# math from https://github.com/pragmagic/godot-nim/blob/7fb22f69af92aa916e56dba14ba3938fc7fa1dd1/godot/core/godotbase.nim

const EPSILON = 0.00001'f32

proc isEqualApprox*(a, b: float32): bool {.inline, noinit.} =
  ## `true` if two numbers are so close that the difference doesn't matter.
  abs(a - b) < EPSILON

proc isEqualApprox*(a, b: float64): bool {.inline, noinit.} =
  abs(a - b) < EPSILON

proc sign*(a: float32): float32 {.inline, noinit.} =
  ## `-1.0` for negative numbers, `1.0` for everything else.
  if a < 0: -1.0'f32 else: 1.0'f32

proc sign*(a: float64): float64 {.inline, noinit.} =
  if a < 0: -1.0'f64 else: 1.0'f64

proc stepify*(value, step: float64): float64 {.inline, noinit.} =
  ## Snap `value` to the nearest multiple of `step`.
  ## `stepify(7.3, 5.0)` is `5.0`. `stepify(8.0, 5.0)` is `10.0`.
  if step != 0'f64:
    floor(value / step + 0.5'f64) * step
  else:
    value

proc stepify*(value, step: float32): float32 {.inline, noinit.} =
  if step != 0'f32:
    floor(value / step + 0.5'f32) * step
  else:
    value

# Vector3 math. https://github.com/pragmagic/godot-nim/blob/7fb22f69af92aa916e56dba14ba3938fc7fa1dd1/godot/core/vector3.nim

proc `+`*(a, b: Vector3): Vector3 {.inline.} =
  result.x = a.x + b.x
  result.y = a.y + b.y
  result.z = a.z + b.z

proc `+=`*(a: var Vector3, b: Vector3) {.inline.} =
  a.x += b.x
  a.y += b.y
  a.z += b.z

proc `-`*(a, b: Vector3): Vector3 {.inline.} =
  result.x = a.x - b.x
  result.y = a.y - b.y
  result.z = a.z - b.z

proc `-=`*(a: var Vector3, b: Vector3) {.inline.} =
  a.x -= b.x
  a.y -= b.y
  a.z -= b.z

proc `*`*(a, b: Vector3): Vector3 {.inline.} =
  result.x = a.x * b.x
  result.y = a.y * b.y
  result.z = a.z * b.z

proc `*=`*(a: var Vector3, b: Vector3) {.inline.} =
  a.x *= b.x
  a.y *= b.y
  a.z *= b.z

proc `*`*(a: Vector3, b: float32): Vector3 {.inline.} =
  result.x = a.x * b
  result.y = a.y * b
  result.z = a.z * b

proc `*`*(b: float32, a: Vector3): Vector3 {.inline.} =
  a * b

proc `*=`*(a: var Vector3, b: float32) {.inline.} =
  a.x *= b
  a.y *= b
  a.z *= b

proc `/`*(a, b: Vector3): Vector3 =
  result.x = a.x / b.x
  result.y = a.y / b.y
  result.z = a.z / b.z

proc `/=`*(a: var Vector3, b: Vector3) {.inline.} =
  a.x /= b.x
  a.y /= b.y
  a.z /= b.z

proc `/`*(a: Vector3, b: float32): Vector3 =
  result.x = a.x / b
  result.y = a.y / b
  result.z = a.z / b

proc `/=`*(a: var Vector3, b: float32) {.inline.} =
  a.x /= b
  a.y /= b
  a.z /= b

proc `==`*(a, b: Vector3): bool {.inline.} =
  a.x == b.x and a.y == b.y and a.z == b.z

proc `<`*(a, b: Vector3): bool =
  if a.x == b.x:
    if a.y == b.y:
      return a.z < b.z
    return a.y < b.y
  return a.x < b.x

proc `-`*(self: Vector3): Vector3 =
  result.x = -self.x
  result.y = -self.y
  result.z = -self.z

proc minAxis*(self: Vector3): int {.inline.} =
  if self.x < self.y:
    if self.x < self.z: 0 else: 2
  else:
    if self.y < self.z: 1 else: 2

proc maxAxis*(self: Vector3): int {.inline.} =
  if self.x < self.y:
    if self.y < self.z: 2 else: 1
  else:
    if self.x < self.z: 2 else: 0

proc length*(self: Vector3): float32 {.inline.} =
  ## How long the vector is. If it's the difference between two
  ## positions, this is the distance between them.
  let x2 = self.x * self.x
  let y2 = self.y * self.y
  let z2 = self.z * self.z

  result = sqrt(x2 + y2 + z2)

proc lengthSquared*(self: Vector3): float32 {.inline.} =
  let x2 = self.x * self.x
  let y2 = self.y * self.y
  let z2 = self.z * self.z

  result = x2 + y2 + z2

proc normalize*(self: var Vector3) {.inline.} =
  ## Shrink or stretch the vector so its length is exactly 1, keeping
  ## its direction. A vector like this is handy for pointing at things.
  let len = self.length()
  if len == 0:
    self.x = 0
    self.y = 0
    self.z = 0
  else:
    self.x /= len
    self.y /= len
    self.z /= len

proc normalized*(self: Vector3): Vector3 {.inline.} =
  ## Like `normalize`, but returns a new vector instead of changing
  ## this one.
  result = self
  result.normalize()

proc isNormalized*(self: Vector3): bool {.inline.} =
  self.lengthSquared().isEqualApprox(1.0'f32)

proc zero*(self: var Vector3) {.inline.} =
  self.x = 0
  self.y = 0
  self.z = 0

proc inverse*(self: Vector3): Vector3 {.inline.} =
  vec3(1.0'f32 / self.x, 1.0'f32 / self.y, 1.0'f32 / self.z)

proc cross*(self, other: Vector3): Vector3 {.inline.} =
  vec3(
    self.y * other.z - self.z * other.y,
    self.z * other.x - self.x * other.z,
    self.x * other.y - self.y * other.x,
  )

proc dot*(self, other: Vector3): float32 {.inline.} =
  self.x * other.x + self.y * other.y + self.z * other.z

proc abs*(self: Vector3): Vector3 {.inline.} =
  vec3(abs(self.x), abs(self.y), abs(self.z))

proc sign*(self: Vector3): Vector3 {.inline.} =
  vec3(sign(self.x), sign(self.y), sign(self.z))

proc floor*(self: Vector3): Vector3 {.inline.} =
  vec3(floor(self.x), floor(self.y), floor(self.z))

proc ceil*(self: Vector3): Vector3 {.inline.} =
  vec3(ceil(self.x), ceil(self.y), ceil(self.z))

proc lerp*(self: Vector3, other: Vector3, t: float32): Vector3 {.inline.} =
  ## Blend between two vectors. `t` is how far to go: `0.0` gives you
  ## the first vector, `1.0` gives you the second, `0.5` is halfway.
  vec3(
    self.x + t * (other.x - self.x),
    self.y + t * (other.y - self.y),
    self.z + t * (other.z - self.z),
  )

proc distanceTo*(self, other: Vector3): float32 {.inline.} =
  ## How far apart two positions are.
  (other - self).length()

proc distanceSquaredTo*(self, other: Vector3): float32 {.inline.} =
  (other - self).lengthSquared()

proc angleTo*(self, other: Vector3): float32 {.inline.} =
  arctan2(self.cross(other).length(), self.dot(other))

proc slide*(self, n: Vector3): Vector3 {.inline.} =
  assert(n.isNormalized())
  result = self - n * self.dot(n)

proc reflect*(self, n: Vector3): Vector3 {.inline.} =
  assert(n.isNormalized())
  result = 2.0'f32 * n * self.dot(n) - self

proc bounce*(self, n: Vector3): Vector3 {.inline.} =
  -self.reflect(n)

proc snap*(self: var Vector3, other: Vector3) =
  self.x = stepify(self.x, other.x)
  self.y = stepify(self.y, other.y)
  self.z = stepify(self.z, other.z)

proc snapped*(self: Vector3, other: Vector3): Vector3 =
  result = self
  result.snap(other)

proc cubicInterpolate*(self, b, preA, postB: Vector3, t: float32): Vector3 =
  let p0 = preA
  let p1 = self
  let p2 = b
  let p3 = postB

  let t2 = t * t
  let t3 = t2 * t

  result =
    0.5 * (
      (p1 * 2.0) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4 * p2 - p3) * t2 +
      (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
    )

proc moveToward*(vFrom, to: Vector3, delta: float32): Vector3 =
  ## Take one step of size `delta` from one position toward another,
  ## without overshooting.
  let
    vd = to - vFrom
    vLen = vd.length

  if vLen <= delta or vLen < EPSILON:
    result = to
  else:
    result = vFrom + (vd / vLen) * delta

converter vec3_to_bool*(v: Vector3): bool =
  v != vec3(0, 0, 0)

# WorldBox helpers — axis-aligned world-space bounding box queries.
# Returned by `bounds()` and consumed by `box_is_free`, `units_overlapping`,
# `overlaps`, etc. See `docs/notes/instance-query-api.md`.

proc size*(b: WorldBox): Vector3 {.inline.} =
  ## Width, height and depth of the box, as a `Vector3`.
  b.max - b.min

proc centre*(b: WorldBox): Vector3 {.inline.} =
  ## The point in the middle of the box.
  (b.min + b.max) * 0.5

proc contains*(b: WorldBox, p: Vector3): bool {.inline.} =
  ## `true` if the point is inside the box.
  p.x >= b.min.x and p.x <= b.max.x and p.y >= b.min.y and p.y <= b.max.y and
    p.z >= b.min.z and p.z <= b.max.z

proc intersects*(a, b: WorldBox): bool {.inline.} =
  ## `true` if two boxes overlap.
  not (
    a.max.x < b.min.x or a.min.x > b.max.x or a.max.y < b.min.y or
    a.min.y > b.max.y or a.max.z < b.min.z or a.min.z > b.max.z
  )

proc expanded*(b: WorldBox, margin: float): WorldBox {.inline.} =
  ## A copy of the box, grown by `margin` in every direction.
  (b.min - vec3(margin, margin, margin), b.max + vec3(margin, margin, margin))
