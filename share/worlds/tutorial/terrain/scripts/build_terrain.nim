import std/math

# Island terrain: a U of cliffs (west, east, south), a river from a waterfall
# on the west cliff out to the sea, a big island in the mouth, palms and the
# odd broadleaf or conifer. build_water draws the water to match, so the
# shared shape (coast, river, cliffs, island) must stay identical in both.
#
# Scripts are slow at per-block math, so noise is computed once into small
# grids and tiles, colors come from precomputed ramps, and runs of matching
# columns are drawn as single boxes.

lock = true

# Baked already: the land is saved with the level, so there's nothing to do.
# The west cliff is solid rock here, so this block only exists once baked. To
# regenerate, delete this unit's `edits.bin` from the level's data folder and
# reload.
if has_block_at(vec3(-255, 0, 0)):
  quit()

speed = ASAP

let started = now_seconds()

const
  SEED = 11'u32
  SEA_BASE = 1.1
  OX = 0 # this unit's start position
  OZ = 100
  # land only exists inside this footprint (plus the island)
  X0 = -260
  X1 = 260
  Z0 = -320
  Z1 = 180
  CLIFF_H = 45.0
  WEST_X = -230.0
  EAST_X = 230.0
  SOUTH_Z = 150.0
  ISL_CX = 195
  ISL_CZ = -215
  ISL_R = 52.0
  ISL_TALL = 14.0
  FALLS_Z = -55

# --- noise -----------------------------------------------------------------

proc hash01(ix, iz: int, salt: uint32): float =
  var h =
    cast[uint32](ix) * 0x85ebca6b'u32 xor cast[uint32](iz) * 0xc2b2ae35'u32 xor
    (salt * 0x9e3779b9'u32 + SEED)
  h = h xor (h shr 13)
  h = h * 0x27d4eb2f'u32
  h = h xor (h shr 16)
  float(h and 0xffffff'u32) / float(0xffffff)

template smooth(t: float): float =
  t * t * (3.0 - 2.0 * t)

proc vnoise(x, z: float, salt: uint32, period = 0): float =
  ## Value noise in [0, 1]; wraps every `period` lattice cells if given.
  var
    ix = floor(x).int
    iz = floor(z).int
    jx = ix + 1
    jz = iz + 1
  let
    fx = smooth(x - floor(x))
    fz = smooth(z - floor(z))
  if period > 0:
    ix = ix mod period
    iz = iz mod period
    jx = jx mod period
    jz = jz mod period
  let
    a = hash01(ix, iz, salt)
    b = hash01(jx, iz, salt)
    c = hash01(ix, jz, salt)
    d = hash01(jx, jz, salt)
  (a * (1 - fx) + b * fx) * (1 - fz) + (c * (1 - fx) + d * fx) * fz

proc fbm(x, z: float, salt: uint32, octaves = 3): float =
  var
    total = 0.0
    amp = 1.0
    norm = 0.0
    fx = x
    fz = z
  for o in 0 ..< octaves:
    total += vnoise(fx, fz, salt + uint32(o) * 101) * amp
    norm += amp
    amp *= 0.5
    fx = fx * 2.03 + 17.3
    fz = fz * 2.03 - 9.1
  total / norm

# Smooth fields sampled every S metres over the footprint. Each row blends
# the two grid columns either side of it once, leaving a cheap lerp along z.
const
  S = 8
  GX0 = X0 - 5 * S
  GZ0 = Z0 - 5 * S
  GW = (X1 - X0) div S + 12
  GD = (Z1 - Z0) div S + 12

proc make_grid(scale: float, salt: uint32, octaves = 3): seq[float] =
  result = new_seq[float](GW * GD)
  for gx in 0 ..< GW:
    for gz in 0 ..< GD:
      result[gx * GD + gz] = fbm(
        float(GX0 + gx * S) / scale, float(GZ0 + gz * S) / scale, salt, octaves
      )

proc row_of(g: seq[float], x: int, dst: var seq[float]) =
  let
    fx = float(x - GX0) / S.float
    gx = int(fx)
    tx = fx - gx.float
    b = gx * GD
  for j in 0 ..< GD:
    dst[j] = g[b + j] * (1 - tx) + g[b + GD + j] * tx

template at(r: seq[float], gz: int, tz: float): float =
  r[gz] + (r[gz + 1] - r[gz]) * tz

proc sample(g: seq[float], x, z: int): float =
  let
    fx = float(x - GX0) / S.float
    fz = float(z - GZ0) / S.float
    gx = int(fx)
    gz = int(fz)
    tx = fx - gx.float
    tz = fz - gz.float
    i = gx * GD + gz
  (g[i] * (1 - tx) + g[i + GD] * tx) * (1 - tz) +
    (g[i + 1] * (1 - tx) + g[i + GD + 1] * tx) * tz

# Fine detail from a 64x64 tile that wraps seamlessly.
const T = 64

proc make_tile(cell: int, salt: uint32): seq[float] =
  result = new_seq[float](T * T)
  for tx in 0 ..< T:
    for tz in 0 ..< T:
      var
        total = 0.0
        amp = 1.0
        norm = 0.0
        c = cell
        o = 0'u32
      while c >= 1:
        total += vnoise(tx / c, tz / c, salt + o * 101, period = T div c) * amp
        norm += amp
        amp *= 0.5
        c = c div 2
        o += 1
      result[tx * T + tz] = total / norm

template tile(t: seq[float], x, z: int): float =
  t[(x and (T - 1)) * T + (z and (T - 1))]

# --- the shared shape (keep in step with build_water) ------------------------

let
  detail_t = make_tile(8, 71)
  meadow_g = make_grid(41.0, 70)
  tall_g = make_grid(24.0, 46)
  wobble_g = make_grid(17.0, 55, 2)
  island_g = make_grid(45.0, 60)

proc coast_z(x: int): float =
  ## Sea everywhere north of this line, from the NW headland to the NE mouth.
  -250.0 + (x.float + 260.0) * (180.0 / 520.0) +
    44.0 * (fbm(x.float / 57.0, 3.7, 42) - 0.5)

template west_wobble(z: int): float =
  16.0 * (fbm(z.float / 33.0, 7.1, 43) - 0.5)

template east_wobble(z: int): float =
  16.0 * (fbm(z.float / 33.0, 19.9, 44) - 0.5)

template south_wobble(x: int): float =
  16.0 * (fbm(x.float / 33.0, 31.3, 45) - 0.5)

const RIVER = [
  (-238.0, -55.0),
  (-150.0, -50.0),
  (-40.0, -60.0),
  (70.0, -66.0),
  (135.0, -92.0),
  (172.0, -128.0),
]

var
  river_len = 0.0
  river_runs: seq[float]
for i in 0 ..< RIVER.len - 1:
  river_runs.add river_len
  river_len += sqrt(
    (RIVER[i + 1][0] - RIVER[i][0]) ^ 2 + (RIVER[i + 1][1] - RIVER[i][1]) ^ 2
  )

# The river's centerline runs west to east, so per row it's a point (zc) and
# a slope correction (norm); t is how far along the river we are, 0 to 1.
# A smooth curve through the points, so the banks don't kink at each one.
var river_zc, river_norm, river_t: float

proc river_slope(i: int): float =
  let
    a = RIVER[max(i - 1, 0)]
    b = RIVER[min(i + 1, RIVER.len - 1)]
  (b[1] - a[1]) / (b[0] - a[0])

proc river_row(x: int) =
  let fx = x.float
  for i in 0 ..< RIVER.len - 1:
    let (ax, az) = RIVER[i]
    let (bx, bz) = RIVER[i + 1]
    if fx <= bx:
      let
        w = bx - ax
        u = clamp((fx - ax) / w, 0.0, 1.0)
        ma = river_slope(i) * w
        mb = river_slope(i + 1) * w
        u2 = u * u
        u3 = u2 * u
        slope =
          ((6 * u2 - 6 * u) * az + (3 * u2 - 4 * u + 1) * ma +
            (6 * u - 6 * u2) * bz + (3 * u2 - 2 * u) * mb) / w
      river_zc =
        (2 * u3 - 3 * u2 + 1) * az + (u3 - 2 * u2 + u) * ma + (3 * u2 - 2 * u3) * bz +
        (u3 - u2) * mb
      river_norm = 1.0 / sqrt(1.0 + slope * slope)
      river_t = (river_runs[i] + u * sqrt(w * w + (bz - az) ^ 2)) / river_len
      return
  river_zc = RIVER[^1][1]
  river_norm = 1.0
  river_t = 1.0

template river_dist(x, z: int): float =
  if x.float < RIVER[0][0]:
    sqrt((x.float - RIVER[0][0]) ^ 2 + (z.float - RIVER[0][1]) ^ 2)
  elif x.float > RIVER[^1][0]:
    sqrt((x.float - RIVER[^1][0]) ^ 2 + (z.float - RIVER[^1][1]) ^ 2)
  else:
    abs(z.float - river_zc) * river_norm

proc island_elev(x, z: int): float =
  let
    dx = float(x - ISL_CX)
    dz = float(z - ISL_CZ)
    d2 = dx * dx + dz * dz
  if d2 > 70.0 * 70.0:
    return -1.0
  let t = 1.0 - sqrt(d2) / (ISL_R * (0.7 + 0.6 * sample(island_g, x, z)))
  if t > 0:
    ISL_TALL * pow(t, 1.6) + 2.8 * t * (tile(detail_t, x, z) - 0.4)
  else:
    -1.0

proc cliff_elev(x, z: int, c, ws, ww, we, tall: float): float =
  ## 0 on open land, rising to ~CLIFF_H in the border bands. The bands keep
  ## their height past the coast and plunge into the sea ~40 m out.
  let cd = max(
    max((WEST_X + ww) - x.float, x.float - (EAST_X + we)),
    z.float - (SOUTH_Z + ws),
  )
  if cd <= 0:
    return 0.0
  let fade = smooth(clamp((z.float - (c - 40.0)) / 50.0, 0.0, 1.0))
  (CLIFF_H + 16.0 * (tall - 0.5)) * smooth(clamp(cd / 16.0, 0.0, 1.0)) * fade

# --- colors ------------------------------------------------------------------

proc hex(h: int): Color =
  (
    r: float32((h shr 16) and 0xff) / 255,
    g: float32((h shr 8) and 0xff) / 255,
    b: float32(h and 0xff) / 255,
    a: 1.0'f32,
  )

proc mix(a, b: Color, t: float): Color =
  let t = clamp(t, 0.0, 1.0)
  (
    r: round((a.r + (b.r - a.r) * t) * 32) / 32,
    g: round((a.g + (b.g - a.g) * t) * 32) / 32,
    b: round((a.b + (b.b - a.b) * t) * 32) / 32,
    a: 1.0'f32,
  )

# Every color is an index into `palette`. A ramp is 33 steps from a to b.
var palette: seq[Color]

proc ramp(a, b: Color): int =
  result = palette.len
  for i in 0 .. 32:
    palette.add mix(a, b, i / 32)

proc solid(c: Color): int =
  result = palette.len
  palette.add c

template step(t: float): int =
  int(clamp(t, 0.0, 1.0) * 32 + 0.5)

let
  wet_sand = hex(0xb39c6b)
  low_grass = hex(0x6fbf4e)
  high_grass = hex(0x3e8a30)
  rock = hex(0x7d6a55)
  rock_dark = hex(0x46392c)
  conifer_green = hex(0x235e2b)
  SAND = ramp(wet_sand, hex(0xe8d9a6))
  CLIFF_ROCK = ramp(rock_dark, hex(0x93805f))
  STRATA = ramp(rock_dark, hex(0x6e5a41))
  CRUST = solid(mix(wet_sand, rock, 0.5))
  HILL_ROCK = solid(mix(rock, high_grass, 0.15))
  ROCK_DARK = solid(rock_dark)
  TRUNK = solid(hex(0x6b4a2e))
  CHARCOAL = solid(hex(0x3d3630))
  CONIFER = solid(conifer_green)
  FLOWERS = [
    solid(hex(0xf2f2f2)), solid(hex(0xe06060)), solid(hex(0xffd23d)),
    solid(hex(0xa06de0)),
  ]
  PALM_GREENS = [solid(hex(0x2f7d32)), solid(hex(0x3f9138)), solid(hex(0x25702c))]
  LEAF_GREENS = [solid(hex(0x3c8f30)), solid(hex(0x58a13c)), solid(hex(0x2f7d32))]

# Meadow grass: 9 ramps, each deeper into the shade-green swathes.
const SHADES = 9
let GRASS = palette.len
for s in 0 ..< SHADES:
  let deep = s / (SHADES - 1) * 0.9
  discard ramp(mix(low_grass, hex(0x2e7226), deep), mix(high_grass, hex(0x2e7226), deep))

let
  patch_g = make_grid(13.0, 80, 2)
  shade_g = make_grid(23.0, 82, 2)

# Cliff faces are layered rock: strata by height, drifting slowly along the
# cliff. Tabled at whole steps of u = (x - z) / 70 and blended between.
const
  STRATA_Y = 96
  STRATA_U = 20

var strata = new_seq[float](STRATA_Y * STRATA_U)
for y in 0 ..< STRATA_Y:
  for u in 0 ..< STRATA_U:
    strata[y * STRATA_U + u] = vnoise(y.float / 5.0, (u - 8).float, 48)

# --- rows --------------------------------------------------------------------

const
  NONE = 0
  LAND = 1
  WATER = 2
  ZA = Z0 - 1
  ZB = Z1
  NZ = ZB - ZA + 1
  XA = X0 - 1
  XB = X1 + 8 # the island pokes a little past the footprint

# Three rows (x - 1, x, x + 1) of columns, so slopes and the lowest neighbor
# are on hand while a row is drawn.
var
  kind_r = new_seq[int](3 * NZ)
  elev_r = new_seq[float](3 * NZ)
  cliff_r = new_seq[float](3 * NZ)
  isl_r = new_seq[bool](3 * NZ)
  top_r = new_seq[int](3 * NZ)
  ww_z = new_seq[float](NZ)
  we_z = new_seq[float](NZ)
  gz_z = new_seq[int](NZ)
  tz_z = new_seq[float](NZ)
  meadow_row = new_seq[float](GD)
  tall_row = new_seq[float](GD)
  wobble_row = new_seq[float](GD)
  patch_row = new_seq[float](GD)
  shade_row = new_seq[float](GD)

for i in 0 ..< NZ:
  let z = ZA + i
  ww_z[i] = west_wobble(z)
  we_z[i] = east_wobble(z)
  gz_z[i] = (z - GZ0) div S
  tz_z[i] = float((z - GZ0) mod S) / S.float

template slot(x: int): int =
  (((x mod 3) + 3) mod 3) * NZ

proc fill_row(x: int) =
  let
    s = slot(x)
    c = coast_z(x)
    ws = south_wobble(x)
    in_x = x >= X0 and x < X1
    near_island = abs(x - ISL_CX) < 70
  river_row(x)
  let halfwidth = 11.0 + 26.0 * river_t
  row_of(meadow_g, x, meadow_row)
  row_of(tall_g, x, tall_row)
  row_of(wobble_g, x, wobble_row)
  for i in 0 ..< NZ:
    let
      z = ZA + i
      gz = gz_z[i]
      tz = tz_z[i]
    var
      kind = NONE
      e = 0.0
      cl = 0.0
      isl = false
      ie = -1.0
    if near_island:
      ie = island_elev(x, z)
    if ie > 0.05:
      kind = LAND
      e = ie
      isl = true
    else:
      let
        in_fp = in_x and z >= Z0 and z < Z1
        bank = river_dist(x, z) + 8.0 * (at(wobble_row, gz, tz) - 0.5) - halfwidth
      if in_fp:
        cl = cliff_elev(x, z, c, ws, ww_z[i], we_z[i], at(tall_row, gz, tz))
      if bank < 0:
        kind = WATER
      elif cl > 2.0 or (in_fp and z.float >= c):
        kind = LAND
        # meadow flattens into a beach toward the water
        let
          to_water = min(bank, max((z.float - c) * 0.94, 0.0))
          beach = 0.2 + max(to_water - 1.0, 0.0) * 0.28
        e = max(min(1.6 + 3.2 * at(meadow_row, gz, tz), beach), cl)
      elif z.float < c:
        kind = WATER
    kind_r[s + i] = kind
    elev_r[s + i] = e
    cliff_r[s + i] = cl
    isl_r[s + i] = isl
    top_r[s + i] =
      if kind == LAND: clamp(int(round(SEA_BASE + e)), 0, 120)
      elif kind == WATER: 1
      else: 0

# --- drawing -----------------------------------------------------------------

var draws = 0

proc block_at(x, y, z: int, w, h, d: int, c: int) =
  me.box(w, h, d, vec3(float(x - OX), y.float, float(z - OZ)), palette[c])
  inc draws

template put(x, y, z: int, c: int) =
  block_at(x, y, z, 1, 1, 1, c)

# Runs of identical columns along z merge into one box.
var
  top_z0, top_n, top_y, top_c: int
  body_z0, body_n, body_lo, body_hi, body_c: int

proc flush_runs(x: int) =
  if top_n > 0:
    block_at(x, top_y, top_z0, 1, 1, top_n, top_c)
    top_n = 0
  if body_n > 0:
    block_at(x, body_lo, body_z0, 1, body_hi - body_lo + 1, body_n, body_c)
    body_n = 0

proc add_top(x, z, y, c: int) =
  if top_n > 0 and y == top_y and c == top_c and z == top_z0 + top_n:
    inc top_n
  else:
    if top_n > 0:
      block_at(x, top_y, top_z0, 1, 1, top_n, top_c)
    (top_z0, top_n, top_y, top_c) = (z, 1, y, c)

proc add_body(x, z, lo, hi, c: int) =
  if hi < lo:
    return
  if body_n > 0 and lo == body_lo and hi == body_hi and c == body_c and
      z == body_z0 + body_n:
    inc body_n
  else:
    if body_n > 0:
      block_at(x, body_lo, body_z0, 1, body_hi - body_lo + 1, body_n, body_c)
    (body_z0, body_n, body_lo, body_hi, body_c) = (z, 1, lo, hi, c)

proc surface(x, z, gz: int, tz, e, cl, slope: float): int =
  if cl > 3.0 and cl >= e - 0.01:
    # cliff: rock on the faces, grass wherever it flattens out
    if slope < 1.4:
      return GRASS + step(e / CLIFF_H * 0.7 + at(patch_row, gz, tz) * 0.3)
    return CLIFF_ROCK +
      step(e / CLIFF_H * 0.55 + vnoise(e / 6.5, (x + z) / 90, 47) * 0.45)
  if e < 1.0:
    return SAND + step(e)
  if slope > 1.15 and e > 2.5:
    return HILL_ROCK
  # wildflower flecks keep the meadow lively
  if hash01(x, z, 23) > 0.9955:
    return FLOWERS[int(hash01(x, z, 24) * 3.999)]
  let
    patch = at(patch_row, gz, tz) * 0.6 + tile(detail_t, x + 17, z) * 0.4
    alt = clamp((e - 1.0) / 8.0, 0.0, 1.0)
    deep = (at(shade_row, gz, tz) - 0.55) * 2.0
    shade = if deep > 0: min(int(deep / 0.9 * (SHADES - 1).float + 0.5), SHADES - 1) else: 0
  GRASS + shade * 33 + step(alt * 0.5 + patch * 0.5)

template strata_at(u: float, y: int): int =
  block:
    let
      ui = int(u)
      i = y * STRATA_U + ui
    STRATA + step(strata[i] + (strata[i + 1] - strata[i]) * (u - ui.float))

# --- trees -------------------------------------------------------------------

var trees = 0

proc palm(x, base, z, h: int, r1, r2: float, leaves: int) =
  ## Gently curving trunk, a frond crown that spreads with height, and the
  ## odd coconut.
  let
    lean_x = (r1 - 0.5) * 4.0
    lean_z = (r2 - 0.5) * 4.0
  var
    tx = x
    tz = z
  for i in 0 ..< h:
    let t = i / h
    tx = x + int(round(lean_x * t * t))
    tz = z + int(round(lean_z * t * t))
    put(tx, base + i, tz, TRUNK)
  let
    ty = base + h
    arms = 4 + int(r1 * 3.0)
    reach = 2 + int(h.float * 0.18 + r2 * 2.0)
  put(tx, ty + 1, tz, leaves)
  for a in 0 ..< arms:
    let ang = a.float * (2.0 * PI / arms.float) + r2 * 0.8
    for s in 1 .. reach:
      let droop =
        if s <= reach div 2: 0 else: int(round(float(s - reach div 2) * 0.7))
      put(
        tx + int(round(cos(ang) * s.float)), ty - droop,
        tz + int(round(sin(ang) * s.float)), leaves,
      )
  if h >= 9 and r1 > 0.4:
    put(tx + 1, ty - 1, tz, TRUNK)
    put(tx, ty - 1, tz - 1, TRUNK)
  inc trees

proc broadleaf(x, base, z, h: int, r1, r2, r3: float, bark, leaves: int) =
  ## Straight trunk with a lumpy canopy of three balls.
  block_at(x - 1, base, z, 3, 2, 1, bark)
  block_at(x, base, z - 1, 1, 2, 3, bark)
  block_at(x, base, z, 1, h, 1, bark)
  let
    cr = 2.8 + h.float * 0.18 + r1 * 1.2
    ox = float(x - OX)
    oz = float(z - OZ)
    top = float(base + h)
    c = palette[leaves]
  me.sphere(cr * 2, vec3(ox, top + cr * 0.4, oz), c)
  me.sphere(cr * 1.2, vec3(ox + (r2 - 0.5) * 4.0, top, oz + (r3 - 0.5) * 4.0), c)
  me.sphere(cr, vec3(ox - (r3 - 0.5) * 3.0, top + 1, oz - (r2 - 0.5) * 3.0), c)
  draws += 3
  inc trees

proc conifer(x, base, z, h: int, r1: float) =
  ## Tapered cone on a short trunk.
  block_at(x, base, z, 1, 2, 1, TRUNK)
  let spread = 0.8 + r1 * 0.4
  for i in 0 ..< h:
    let r = max(0.6, float(h - i) * 0.32 * spread)
    me.cylinder(
      r * 2, 1, vec3(float(x - OX), float(base + 2 + i), float(z - OZ)), conifer_green
    )
    inc draws
  put(x, base + 2 + h, z, CONIFER)
  inc trees

const
  CELL = 18
  CW = (XB - X0) div CELL + 1
  CD = (Z1 - Z0) div CELL + 1

# inland trees on a jittered grid: at most one spot per cell
var spots = new_seq[tuple[x, z: int]](CW * CD)
for cx in 0 ..< CW:
  for cz in 0 ..< CD:
    spots[cx * CD + cz] =
      if hash01(cx, cz, 32) < 0.22:
        (
          X0 + cx * CELL + int(hash01(cx, cz, 30) * (CELL - 4).float) + 2,
          Z0 + cz * CELL + int(hash01(cx, cz, 31) * (CELL - 4).float) + 2,
        )
      else:
        (int.high, int.high)

proc cliff_at(x, z: int): float =
  cliff_elev(
    x, z, coast_z(x), south_wobble(x), west_wobble(z), east_wobble(z),
    sample(tall_g, x, z),
  )

proc maybe_tree(x, z, top: int, e: float, isl: bool) =
  if x < -200 and abs(z - FALLS_Z) < 20:
    return # keep fronds clear of the falls
  # dense small palms along the coasts and on the island
  if (isl or e < 2.4) and hash01(x, z, 20) > (if isl: 0.9968 else: 0.9987):
    palm(
      x, top + 1, z, 5 + int(hash01(x, z, 21) * 6.0), hash01(x, z, 22),
      hash01(x, z, 25), PALM_GREENS[int(hash01(x, z, 26) * 2.999)],
    )
    return
  if x < X0:
    return
  let
    cx = (x - X0) div CELL
    cz = (z - Z0) div CELL
    spot = spots[cx * CD + cz]
  if x != spot.x or z != spot.z:
    return
  if cliff_at(x + 7, z) >= 6.0 or cliff_at(x - 7, z) >= 6.0 or
      cliff_at(x, z + 7) >= 6.0 or cliff_at(x, z - 7) >= 6.0:
    return
  let
    r1 = hash01(cx, cz, 33)
    r2 = hash01(cx, cz, 34)
    r3 = hash01(cx, cz, 35)
    pick = hash01(cx, cz, 36)
  if pick < 0.72:
    palm(x, top + 1, z, 6 + int(r1 * 10.0), r1, r2, PALM_GREENS[int(r3 * 2.999)])
  elif pick < 0.9:
    broadleaf(
      x, top + 1, z, 5 + int(r2 * 7.0), r1, r2, r3,
      if hash01(cx, cz, 37) < 0.5: TRUNK else: CHARCOAL,
      LEAF_GREENS[int(r1 * 2.999)],
    )
  else:
    conifer(x, top + 1, z, 8 + int(r3 * 10.0), r1)

proc draw_row(x: int) =
  let
    sp = slot(x - 1)
    s = slot(x)
    sn = slot(x + 1)
  row_of(patch_g, x, patch_row)
  row_of(shade_g, x, shade_row)
  for i in 1 ..< NZ - 1:
    if kind_r[s + i] != LAND:
      continue
    let
      z = ZA + i
      e = elev_r[s + i]
      cl = cliff_r[s + i]
      hi = top_r[s + i]
      slope = max(
        abs(elev_r[sn + i] - elev_r[sp + i]),
        abs(elev_r[s + i + 1] - elev_r[s + i - 1]),
      )
      lo = min(
        min(
          min(min(hi, top_r[sp + i - 1]), min(top_r[sp + i], top_r[sp + i + 1])),
          min(top_r[s + i - 1], top_r[s + i + 1]),
        ),
        min(min(top_r[sn + i - 1], top_r[sn + i]), top_r[sn + i + 1]),
      )
    add_top(x, z, hi, surface(x, z, gz_z[i], tz_z[i], e, cl, slope))
    if cl > 3.0:
      # cliffs are solid rock: plain fill out of sight, strata on the faces
      add_body(x, z, 0, lo - 1, ROCK_DARK)
      let u = (x - z) / 70 + 8.0
      var
        y0 = lo
        c0 = strata_at(u, lo)
      for y in lo + 1 .. hi:
        let c = if y < hi: strata_at(u, y) else: -1
        if c != c0:
          block_at(x, y0, z, 1, y - y0, 1, c0)
          y0 = y
          c0 = c
    else:
      add_body(x, z, lo, hi - 1, CRUST)
      if e > 1.0:
        maybe_tree(x, z, hi, e, isl_r[s + i])
  flush_runs(x)

# --- main ----------------------------------------------------------------------

fill_row(XA)
fill_row(XA + 1)
for x in XA + 1 ..< XB:
  fill_row(x + 1)
  draw_row(x)
persist()
save_level_now()
echo "terrain: ", draws, " draws, ", trees, " trees in ",
  round(now_seconds() - started, 1), "s"
