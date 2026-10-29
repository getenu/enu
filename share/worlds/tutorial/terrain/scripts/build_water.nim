import std/math

# The sea, the river and the waterfall for build_terrain's island, first
# frame only. Its own unit so it can animate without redrawing the land. The
# shared shape below is copied from build_terrain and must stay identical, or
# the shorelines won't meet.
#
# Near the land the water is drawn per metre; the open sea beyond is drawn in
# 2 m cells.

lock = true

const
  FRAMES = 24 # one loop of the animation...
  LOOP = 3.0 # ...lasting this many seconds

# Baked already: the frames and the still sea are saved with the level, so
# just play them. To regenerate, delete this unit's `edits.bin` and `frames`
# from the level's data folder and reload.
if me.frame_count > 0:
  play(FRAMES.float / LOOP)
  quit()

speed = ASAP
let started = now_seconds()

const
  SEED = 11'u32
  SEA_BASE = 1.1
  OX = 0 # this unit's start position
  OZ = -400
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

# Colors are mixed as plain floats and snapped to 1/32 steps; `key` packs the
# snapped color into an int, and `color_of` builds each Color once.
type Rgb = tuple[r, g, b: float]

proc rgb(h: int): Rgb =
  (((h shr 16) and 0xff) / 255, ((h shr 8) and 0xff) / 255, (h and 0xff) / 255)

const
  DEEP = rgb(0x082f66)
  MID = rgb(0x1565c0)
  CREST = rgb(0x3f9be8)
  SHALLOW = rgb(0x46c6b8)
  FOAM = rgb(0xf2f8fc)
  RIVER_FOAM: Rgb = (
    CREST.r + (FOAM.r - CREST.r) * 0.6,
    CREST.g + (FOAM.g - CREST.g) * 0.6,
    CREST.b + (FOAM.b - CREST.b) * 0.6,
  )

template key(c: Rgb): int =
  int(clamp(c.r, 0.0, 1.0) * 32 + 0.5) * 1089 +
    int(clamp(c.g, 0.0, 1.0) * 32 + 0.5) * 33 + int(clamp(c.b, 0.0, 1.0) * 32 + 0.5)

template blend(c: var Rgb, to: Rgb, t: float) =
  let amount = clamp(t, 0.0, 1.0)
  c.r += (to.r - c.r) * amount
  c.g += (to.g - c.g) * amount
  c.b += (to.b - c.b) * amount

var
  known = new_seq[bool](33 * 33 * 33)
  colors = new_seq[Color](33 * 33 * 33)

proc color_of(k: int): Color =
  if not known[k]:
    known[k] = true
    colors[k] = (
      r: float32(k div 1089) / 32,
      g: float32((k div 33) mod 33) / 32,
      b: float32(k mod 33) / 32,
      a: 1.0'f32,
    )
  colors[k]

let
  DEEP_KEY = key(DEEP)
  MID_KEY = key(MID)
  FOAM_KEY = key(FOAM)

# --- waves -------------------------------------------------------------------

# Plane waves split into x and z parts, so each column is a few lookups:
# sin(a + b) = sin(a)cos(b) + cos(a)sin(b).
const
  WX0 = -500
  WX1 = 500
  WAVES = [(43.0, 20.0, 0.0, 0.42), (17.0, -35.0, 1.7, 0.30), (7.2, 65.0, 4.1, 0.20)]

var wsx, wcx: seq[seq[float]]
for (length, angle, phase, _) in WAVES:
  let
    a = angle * PI / 180.0
    k = 2.0 * PI / length
  var sx, cx: seq[float]
  for v in WX0 ..< WX1:
    sx.add sin(v.float * cos(a) * k)
    cx.add cos(v.float * cos(a) * k)
  wsx.add sx
  wcx.add cx

# The z half carries time. Each wave's speed is nudged so it travels a whole
# number of wavelengths per loop, so the last frame runs into the first.
var sz0, cz0, sz1, cz1, sz2, cz2: seq[float]

proc wave_time(t: float) =
  var halves: seq[(seq[float], seq[float])]
  for (length, angle, phase, _) in WAVES:
    let
      a = angle * PI / 180.0
      k = 2.0 * PI / length
      cycles = max(1.0, round(sqrt(9.81 * length / (2.0 * PI)) * LOOP / length))
      shift = phase - k * (cycles * length / LOOP) * t
    var sz, cz: seq[float]
    for v in WX0 ..< WX1:
      sz.add sin(v.float * sin(a) * k + shift)
      cz.add cos(v.float * sin(a) * k + shift)
    halves.add (sz, cz)
  (sz0, cz0) = halves[0]
  (sz1, cz1) = halves[1]
  (sz2, cz2) = halves[2]

# Per frame: how far the chop and churn have drifted round their little
# circles, and how far the river's and the falls' streaks have travelled.
var chop_dx, chop_dz, churn_dx, churn_dz, stream: int

let
  chop_t = make_tile(4, 50) # fine chop on top of the swell
  fleck_t = make_tile(1, 11) # stray foam flecks
  churn_t = make_tile(4, 92) # the plunge pool's churn

# Wave groups: the shortest wave swells and fades in patches.
const
  GS = 16
  GN = (WX1 - WX0) div GS + 2

var groups = new_seq[float](GN * GN)
for gx in 0 ..< GN:
  for gz in 0 ..< GN:
    groups[gx * GN + gz] = vnoise(
      float(WX0 + gx * GS) / 26.0, float(WX0 + gz * GS) / 26.0, 40
    )

# The x half of every wave term is fixed along a row.
var
  sx0, cx0, sx1, cx1, sx2, cx2: float
  group_row = new_seq[float](GN)

proc wave_row(x: int) =
  let
    i = x - WX0
    fx = i / GS
    gx = int(fx)
    tx = fx - gx.float
  sx0 = 0.42 * wsx[0][i]
  cx0 = 0.42 * wcx[0][i]
  sx1 = 0.30 * wsx[1][i]
  cx1 = 0.30 * wcx[1][i]
  sx2 = 0.20 * wsx[2][i]
  cx2 = 0.20 * wcx[2][i]
  for j in 0 ..< GN:
    group_row[j] = groups[gx * GN + j] * (1 - tx) + groups[(gx + 1) * GN + j] * tx

template wave_at(x, z: int): float =
  ## Sea surface offset in metres, roughly [-1, 1].
  block:
    let
      j = z - WX0
      fz = j / GS
      gz = int(fz)
      group = group_row[gz] + (group_row[gz + 1] - group_row[gz]) * (fz - gz.float)
    sx0 * cz0[j] + cx0 * sz0[j] + sx1 * cz1[j] + cx1 * sz1[j] +
      (0.4 + 0.6 * group) * (sx2 * cz2[j] + cx2 * sz2[j]) +
      0.18 * (tile(chop_t, x + chop_dx, z + chop_dz) - 0.5)

# --- near the land: per metre ---

const
  FALLS_X = -230
  NX0 = X0 - 30
  NX1 = X1 + 30
  ZA = Z0 - 30
  ZB = Z1 - 1
  NZ = ZB - ZA + 1

var
  lanes = new_seq[float](NZ)
  ww_z = new_seq[float](NZ)
  we_z = new_seq[float](NZ)
  gz_z = new_seq[int](NZ)
  tz_z = new_seq[float](NZ)
  tall_row = new_seq[float](GD)
  wobble_row = new_seq[float](GD)
  tops = new_seq[int](NZ) # this row's water tops, for the falls
  front_tops: seq[int] # the tops just in front of the falls

const FACE = FALLS_X - 7 # the waterfall's face

for i in 0 ..< NZ:
  let z = ZA + i
  lanes[i] = fbm(z.float * 0.9, 15.3, 97, 2)
  ww_z[i] = west_wobble(z)
  we_z[i] = east_wobble(z)
  gz_z[i] = (z - GZ0) div S
  tz_z[i] = float((z - GZ0) mod S) / S.float

# --- drawing -----------------------------------------------------------------

var draws = 0

proc block_at(x, y, z: int, w, h, d: int, k: int) =
  me.box(w, h, d, vec3(float(x - OX), y.float, float(z - OZ)), color_of(k))
  inc draws

# Every water cell sits on a 1-deep slab, drawn per span before its cells.
# Surfaces of matching cells along z merge into one box, and so does the
# fill under surfaces standing higher than 1.
var
  srf_x, srf_z0, srf_n, srf_w, srf_y, srf_k: int
  mid_x, mid_z0, mid_n, mid_w, mid_h: int

proc slab(x, z0, z1, w: int) =
  if z1 > z0:
    block_at(x, 0, z0, w, 1, z1 - z0, DEEP_KEY)

proc flush_runs() =
  if srf_n > 0:
    block_at(srf_x, srf_y, srf_z0, srf_w, 1, srf_n * srf_w, srf_k)
    srf_n = 0
  if mid_n > 0:
    block_at(mid_x, 1, mid_z0, mid_w, mid_h, mid_n * mid_w, DEEP_KEY)
    mid_n = 0

proc add_cell(x, z, w, y, k: int) =
  ## A water cell `w` metres square with surface color `k` at height `y`.
  if srf_n > 0 and x == srf_x and w == srf_w and y == srf_y and k == srf_k and
      z == srf_z0 + srf_n * w:
    inc srf_n
  else:
    if srf_n > 0:
      block_at(srf_x, srf_y, srf_z0, srf_w, 1, srf_n * srf_w, srf_k)
    (srf_x, srf_z0, srf_n, srf_w, srf_y, srf_k) = (x, z, 1, w, y, k)
  if y >= 2:
    if mid_n > 0 and x == mid_x and w == mid_w and y - 1 == mid_h and
        z == mid_z0 + mid_n * w:
      inc mid_n
    else:
      if mid_n > 0:
        block_at(mid_x, 1, mid_z0, mid_w, mid_h, mid_n * mid_w, DEEP_KEY)
      (mid_x, mid_z0, mid_n, mid_w, mid_h) = (x, z, 1, w, y - 1)

proc sea_color(x, z: int, h, open_sea, shore: float): int =
  ## Crests light, troughs deep; the river runs darker; foam near shore and
  ## on the breaking crests.
  let
    hc = h / (0.35 + 0.65 * open_sea)
    t = clamp((hc + 1.0) / 2.0, 0.0, 1.0)
  var c = DEEP
  if t < 0.5:
    c.blend(MID, t / 0.5)
  else:
    c = MID
    c.blend(CREST, (t - 0.5) / 0.5)
  c.blend(DEEP, 0.30 * (1.0 - open_sea))
  if open_sea < 0.75:
    # foam lanes, dashes and streaks running downstream
    let
      lane = lanes[z - ZA]
      xw = (((x - stream) mod 48) + 48) mod 48
      dash = hash01(z, xw div 3, 98)
      run = hash01(z * 7, xw div 8, 99)
    var streak = 0.0
    if lane > 0.62:
      streak += 0.35
    elif lane > 0.55:
      streak += 0.15
    if dash > 0.80:
      streak += 0.35
    if run > 0.86:
      streak += 0.3
    if streak > 0:
      c.blend(RIVER_FOAM, min(streak, 1.0) * 0.65 * (1.0 - open_sea))
  let e = -shore * 0.06
  if e > -1.0:
    c.blend(SHALLOW, (e + 1.0) * 0.85)
  # plunge pool: churned white below the falls
  let pool =
    if abs(x - FALLS_X) < 25 and abs(z - FALLS_Z) < 21:
      sqrt(float((x - FALLS_X - 4) ^ 2 + (z - FALLS_Z) ^ 2))
    else:
      99.0
  if pool < 20.0:
    let churn = tile(churn_t, x + churn_dx, z + churn_dz)
    c.blend(FOAM, (1.0 - pool / 20.0) * (0.4 + 0.6 * churn))
    if x > -238 and x < -229 and abs(z - FALLS_Z) < 11:
      c.blend(FOAM, 0.65 + 0.35 * churn)
  if e > -0.18:
    return FOAM_KEY
  if e > -0.55:
    c.blend(FOAM, (e + 0.55) / 0.55 * 0.55)
  if open_sea > 0.5 and h > 0.55 and
      tile(chop_t, x + 31 + chop_dx, z + chop_dz) > 0.72:
    c.blend(FOAM, 0.9)
  elif h > 0.0 and tile(fleck_t, x, z) > 0.9975:
    return FOAM_KEY
  key(c)

proc land_top(x, z: int): int =
  ## build_terrain's height for a column (0 for water), for the falls.
  let c = coast_z(x)
  river_row(x)
  if river_dist(x, z) + 8.0 * (sample(wobble_g, x, z) - 0.5) <
      11.0 + 26.0 * river_t:
    return 0
  let
    cl = cliff_elev(
      x, z, c, south_wobble(x), west_wobble(z), east_wobble(z), sample(tall_g, x, z)
    )
    meadow = 1.6 + 3.2 * sample(meadow_g, x, z)
  clamp(int(round(SEA_BASE + max(min(meadow, 0.2), cl))), 0, 120)

const NW = NX1 - NX0

var
  wet = new_seq[bool](NW * NZ)
  shore_d = new_seq[float](NW * NZ) # metres to the nearest land

proc classify_row(x: int) =
  ## Same rules as build_terrain's fill_row: which columns are water, and
  ## which are land for the shoreline distance.
  let
    b = (x - NX0) * NZ
    c = coast_z(x)
    ws = south_wobble(x)
    in_x = x >= X0 and x < X1
    near_island = abs(x - ISL_CX) < 70
  river_row(x)
  let halfwidth = 11.0 + 26.0 * river_t
  row_of(tall_g, x, tall_row)
  row_of(wobble_g, x, wobble_row)
  for i in 0 ..< NZ:
    let z = ZA + i
    shore_d[b + i] = 1e9
    if near_island and island_elev(x, z) > 0.05:
      shore_d[b + i] = 0
      continue
    let
      in_fp = in_x and z >= Z0 and z < Z1
      rd = river_dist(x, z)
    # the wobble moves the banks at most 4 m
    if rd < halfwidth + 5 and
        rd + 8.0 * (at(wobble_row, gz_z[i], tz_z[i]) - 0.5) < halfwidth:
      wet[b + i] = true
      continue
    block:
      var cl = 0.0
      if in_fp:
        cl = cliff_elev(x, z, c, ws, ww_z[i], we_z[i], at(tall_row, gz_z[i], tz_z[i]))
      if cl > 2.0 or (in_fp and z.float >= c):
        shore_d[b + i] = 0
        continue
      if z.float >= c:
        continue # bare ground outside the footprint
    wet[b + i] = true

proc measure_shore() =
  ## Chamfer distance: two sweeps carry each cell's distance to land from
  ## its already-visited neighbors.
  for xi in 0 ..< NW:
    for i in 0 ..< NZ:
      let k = xi * NZ + i
      var v = shore_d[k]
      if v == 0:
        continue
      if xi > 0:
        v = min(v, shore_d[k - NZ] + 1.0)
        if i > 0:
          v = min(v, shore_d[k - NZ - 1] + 1.41)
        if i < NZ - 1:
          v = min(v, shore_d[k - NZ + 1] + 1.41)
      if i > 0:
        v = min(v, shore_d[k - 1] + 1.0)
      shore_d[k] = v
  for xi in countdown(NW - 1, 0):
    for i in countdown(NZ - 1, 0):
      let k = xi * NZ + i
      var v = shore_d[k]
      if v == 0:
        continue
      if xi < NW - 1:
        v = min(v, shore_d[k + NZ] + 1.0)
        if i > 0:
          v = min(v, shore_d[k + NZ - 1] + 1.41)
        if i < NZ - 1:
          v = min(v, shore_d[k + NZ + 1] + 1.41)
      if i < NZ - 1:
        v = min(v, shore_d[k + 1] + 1.0)
      shore_d[k] = v

proc near_row(x: int) =
  let
    b = (x - NX0) * NZ
    c = coast_z(x)
  wave_row(x)
  var span = -1
  for i in 0 .. NZ:
    let w = i < NZ and wet[b + i]
    if w and span < 0:
      span = i
    elif not w and span >= 0:
      slab(x, ZA + span, ZA + i, 1)
      span = -1
  for i in 0 ..< NZ:
    tops[i] = -1
    if not wet[b + i]:
      continue
    let
      z = ZA + i
      open_sea = clamp((c - z.float) / 35.0, 0.0, 1.0)
      h = wave_at(x, z) * (0.35 + 0.65 * open_sea)
      top = clamp(int(round(SEA_BASE + h)), 0, 120)
    tops[i] = top
    add_cell(x, z, 1, top, sea_color(x, z, h, open_sea, shore_d[b + i]))
  flush_runs()

proc falls_streak(z, y: int, phase: float): float =
  ## Curtain foam in [0, 1]: vertical foam lines plus falling flecks and runs.
  let
    zi = z * 31 + int(phase * 5.0)
    yw = (((y + stream) mod 24) + 24) mod 24
    col = fbm(z.float * 1.1, 4.7, 94, 2)
    fleck = hash01(zi, yw div 2, 95)
    run = hash01(zi * 7, yw div 6, 96)
  if col > 0.60:
    result += 0.45
  elif col > 0.52:
    result += 0.2
  if fleck > 0.72:
    result += 0.35
  if run > 0.8:
    result += 0.3
  result = clamp(result, 0.0, 1.0)

proc curtain_key(streak: float): int =
  var c = CREST
  c.blend(FOAM, 0.2 + 0.7 * streak)
  key(c)

proc falls() =
  ## A solid streaked wedge filling the cliff notch at the river head, from
  ## the curtain face back to the rock and up to the lip, plus froth at its
  ## foot and spray bulging off the face.
  for dz in -9 .. 9:
    let z = FALLS_Z + dz
    var back, wall_top = 0
    for step in 1 .. 20:
      let t = land_top(FACE - step, z)
      if t > 25:
        back = step
        wall_top = t
        break
    if wall_top == 0:
      continue
    for bx in 0 ..< back:
      if land_top(FACE - bx, z) > 0:
        continue
      let lip = wall_top - (if bx == 0: 2 elif bx == 1: 1 else: 0)
      for y in 2 .. lip:
        block_at(FACE - bx, y, z, 1, 1, 1, curtain_key(falls_streak(z, y, bx.float * 0.4)))
    let front = front_tops[z - ZA]
    if front >= 0:
      for y in front + 3 .. wall_top - 4:
        if falls_streak(z, y, -0.4) > 0.62:
          block_at(FACE + 1, y, z, 1, 1, 1, curtain_key(0.8))
  # froth mounds where the curtain meets the river
  for x in -236 .. -231:
    for dz in -9 .. 9:
      if fbm(float(x + churn_dx) / 3.1, float(FALLS_Z + dz + churn_dz) / 3.1, 93) >
          0.5:
        block_at(x, 2, FALLS_Z + dz, 1, 1, 1, FOAM_KEY)

# --- main ----------------------------------------------------------------------

for x in NX0 ..< NX1:
  classify_row(x)
measure_shore()

proc draw_frame() =
  for x in NX0 ..< NX1:
    near_row(x)
    if x == FACE + 1:
      front_tops = tops
  falls()
  # The open sea beyond, in 2 m cells. Nothing but water out here.
  for x in countup(WX0, WX1 - 2, 2):
    let
      near = x >= NX0 and x < NX1
      c = coast_z(x)
    var z_end = WX0
    while z_end < WX1 and z_end.float < c and not (near and z_end >= ZA):
      z_end += 2
    wave_row(x)
    slab(x, WX0, z_end, 2)
    for z in countup(WX0, z_end - 2, 2):
      let
        h = wave_at(x, z)
        top = clamp(int(round(SEA_BASE + h)), 0, 120)
      add_cell(x, z, 2, top, sea_color(x, z, h, 1.0, 1e9))
    flush_runs()

clear_frames()
for f in 0 ..< FRAMES:
  if f > 0:
    me.reset(clear = true) # back to an empty sea; saved frames stay
    speed = ASAP
  let
    t = LOOP * f.float / FRAMES.float
    turn = 2.0 * PI * f.float / FRAMES.float
  wave_time(t)
  chop_dx = int(round(1.5 * (cos(turn) - 1.0)))
  chop_dz = int(round(1.5 * sin(turn)))
  churn_dx = int(round(2.2 * (cos(turn) - 1.0)))
  churn_dz = int(round(2.2 * sin(turn)))
  stream = 2 * f
  draw_frame()
  save()
  echo "water: frame ", f + 1, "/", FRAMES, " at ", round(now_seconds() - started, 1), "s"

# The still sea under the animation (what you walk on) is the first frame.
load_frame(0)
persist()
save_level_now()
echo "water: baked ", FRAMES, " frames, ", draws, " draws in ",
  round(now_seconds() - started, 1), "s"
play(FRAMES.float / LOOP)
