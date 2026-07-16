## Generates the 0.3 course level terrain: a U of cliffs (east, west, south),
## a waterfall on the west cliff feeding a river that runs east and bends
## north into the sea, a large island in the mouth, a second land mass to the
## north-west, and open sea to the northern horizon. Same look/vocabulary as
## demo_sea (noise, palette, palms).
##
## Two builds so the water can animate later without re-baking the land:
## `build_terrain` (land + cliffs, static forever) and `build_water`
## (sea + river + falls). Static for now.
##
## Env overrides: ISL_ADDR (host:port of a listening Enu), ISL_SAVE=1
## (persist with the level — stable ids; kill any prior run first),
## ISL_PACE (seconds between emit bands).
import std/[math, os, strutils]
import client
import core, models/[builds, things, colors, voxels]

proc env_f(name: string, default: float): float =
  let v = get_env(name)
  if v == "": default else: v.parse_float

let
  SAVE = get_env("ISL_SAVE") == "1"
  PACE = env_f("ISL_PACE", 0.3)
  ADDR = get_env("ISL_ADDR")
  FRAMES = int(env_f("ISL_FRAMES", 0)) # >0: flipbook of N water frames
  LOOP = env_f("ISL_LOOP", 3.0) # seconds per animation loop
  FRAME_PACE = env_f("ISL_FRAME_PACE", 1.5) # settle time between frames

const
  SEA_BASE = 1.1 # mean water surface height, metres above ground
  SEED = 11'u32
  KIND = PERSISTED

  # Play footprint: land only exists inside it; sea reaches the plane edge.
  X0 = -260.0
  X1 = 260.0
  Z0 = -320.0
  Z1 = 180.0
  G = 500 # grid half-extent; the ground plane runs to ±500
  DIM = 2 * G

  CLIFF_H = 45.0
  WEST_X = -230.0 # inner edges of the cliff bands
  EAST_X = 230.0
  SOUTH_Z = 150.0

# --- deterministic noise (demo_sea) ------------------------------------------

proc hash01(ix, iz: int, salt: uint32): float =
  var h =
    cast[uint32](ix) * 0x85ebca6b'u32 xor cast[uint32](iz) * 0xc2b2ae35'u32 xor
    (salt * 0x9e3779b9'u32 + SEED)
  h = h xor (h shr 13)
  h = h * 0x27d4eb2f'u32
  h = h xor (h shr 16)
  float(h and 0xffffff'u32) / float(0xffffff)

proc smooth(t: float): float =
  t * t * (3.0 - 2.0 * t)

proc vnoise(x, z: float, salt: uint32): float =
  ## Value noise in [0, 1].
  let
    ix = floor(x).int
    iz = floor(z).int
    fx = smooth(x - floor(x))
    fz = smooth(z - floor(z))
    a = hash01(ix, iz, salt)
    b = hash01(ix + 1, iz, salt)
    c = hash01(ix, iz + 1, salt)
    d = hash01(ix + 1, iz + 1, salt)
  (a * (1 - fx) + b * fx) * (1 - fz) + (c * (1 - fx) + d * fx) * fz

proc fbm(x, z: float, salt: uint32, octaves = 4): float =
  ## Fractal noise in [0, 1].
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

# --- waves (demo_sea, static time) --------------------------------------------

var sea_time = 0.0

proc dir_wave(x, z, wavelength, angle_deg, phase: float): float =
  ## A plane wave with deep-water dispersion. In flipbook mode each speed is
  ## snapped a few percent so the wave completes whole cycles in LOOP seconds
  ## — frame N-1 wraps seamlessly to frame 0 (demo_sea's trick).
  let
    a = angle_deg * PI / 180.0
    k = 2.0 * PI / wavelength
  var speed = sqrt(9.81 * wavelength / (2.0 * PI))
  if FRAMES > 0:
    let cycles = max(1.0, round(speed * LOOP / wavelength))
    speed = cycles * wavelength / LOOP
  sin((x * cos(a) + z * sin(a)) * k - k * speed * sea_time + phase)

proc river_flow_streak(x, z: float): float =
  ## Falls-style foam pattern for the river surface: static lanes carrying
  ## foam lines, plus dashes and longer streaks sliding downstream (west ->
  ## east) at 16 m/s — 2 voxels per frame. The pattern grid wraps at P and
  ## 24 frames x 2 voxels = one full wrap, so the loop is exact.
  const P = 48
  let
    drift = if FRAMES > 0: P.float * sea_time / LOOP else: 0.0
    xw = ((int(floor(x - drift)) mod P) + P) mod P
    zi = int(floor(z))
    lane = fbm(z * 0.9, 15.3, 97, 2) # which lanes carry foam lines
    dash = hash01(zi, xw div 3, 98) # short dashes sliding east
    run = hash01(zi * 7, xw div 8, 99) # longer streaks
  if lane > 0.62:
    result += 0.35
  elif lane > 0.55:
    result += 0.15
  if dash > 0.80:
    result += 0.35
  if run > 0.86:
    result += 0.3
  result = clamp(result, 0.0, 1.0)

proc wave_height(x, z: float): float =
  ## Sea surface offset in metres, roughly [-1, 1]. In flipbook mode the
  ## noise fields drift in a small circle so they loop with LOOP.
  var wx, wz: float
  if FRAMES > 0:
    let phase = 2.0 * PI * sea_time / LOOP
    wx = x + 1.5 * (cos(phase) - 1.0)
    wz = z + 1.5 * sin(phase)
  else:
    wx = x + sea_time * 1.1
    wz = z + sea_time * 0.4
  let groups = 0.4 + 0.6 * vnoise(wx / 26.0, wz / 26.0, 40)
  result = 0.42 * dir_wave(x, z, 43.0, 20.0, 0.0)
  result += 0.30 * dir_wave(x, z, 17.0, -35.0, 1.7)
  result += 0.20 * groups * dir_wave(x, z, 7.2, 65.0, 4.1)
  result += 0.18 * (fbm(wx / 3.1, wz / 3.1, 50, 3) - 0.5)

# --- layout --------------------------------------------------------------------

proc coast_z(x: float): float =
  ## Sea everywhere north of this line: NW headland to the NE river mouth.
  -250.0 + (x + 260.0) * (180.0 / 520.0) +
    44.0 * (fbm(x / 57.0, 3.7, 42, 3) - 0.5)

const RIVER = [
  (-238.0, -55.0),
  (-150.0, -50.0),
  (-40.0, -60.0),
  (70.0, -66.0),
  (135.0, -92.0),
  (172.0, -128.0),
]

proc river_dist(x, z: float): tuple[d, t: float] =
  ## Distance to the river centerline and normalized position along it.
  result = (1e9, 0.0)
  var run = 0.0
  var total = 0.0
  for i in 0 ..< RIVER.len - 1:
    total += sqrt(
      (RIVER[i + 1][0] - RIVER[i][0]) ^ 2 + (RIVER[i + 1][1] - RIVER[i][1]) ^ 2
    )
  for i in 0 ..< RIVER.len - 1:
    let
      ax = RIVER[i][0]
      az = RIVER[i][1]
      bx = RIVER[i + 1][0]
      bz = RIVER[i + 1][1]
      seg = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      t = clamp(((x - ax) * (bx - ax) + (z - az) * (bz - az)) / (seg * seg), 0.0, 1.0)
      px = ax + t * (bx - ax)
      pz = az + t * (bz - az)
      d = sqrt((x - px) ^ 2 + (z - pz) ^ 2)
    if d < result.d:
      result = (d, (run + t * seg) / total)
    run += seg

proc river_halfwidth(t: float): float =
  11.0 + 26.0 * t

const
  ISL_CX = 195.0
  ISL_CZ = -215.0
  ISL_R = 52.0
  ISL_TALL = 14.0

proc island_elev(x, z: float): float =
  ## Metres above (positive) or below (negative, capped) sea level.
  let
    dx = x - ISL_CX
    dz = z - ISL_CZ
    d = sqrt(dx * dx + dz * dz)
    wobble = 0.7 + 0.6 * fbm(x / 45.0 + ISL_CX, z / 45.0 + ISL_CZ, 60, 3)
    rr = ISL_R * wobble
    t = 1.0 - d / rr
  if t > -0.6:
    if t > 0:
      ISL_TALL * pow(t, 1.6) + 2.8 * t * (fbm(x / 9.0, z / 9.0, 70, 3) - 0.4)
    else:
      t * 3.0 # underwater skirt
  else:
    -2.0

proc cliff_elev(x, z: float): float =
  ## Height of the cliff field: 0 on open land, rising to ~CLIFF_H in the
  ## border bands. Fades to nothing as the bands run into the sea (headlands).
  let
    ww = 8.0 * (fbm(z / 33.0, 7.1, 43, 3) - 0.5) * 2.0
    we = 8.0 * (fbm(z / 33.0, 19.9, 44, 3) - 0.5) * 2.0
    ws = 8.0 * (fbm(x / 33.0, 31.3, 45, 3) - 0.5) * 2.0
    cd = max(max((WEST_X + ww) - x, x - (EAST_X + we)), z - (SOUTH_Z + ws))
  if cd <= 0:
    return 0.0
  let
    tall = CLIFF_H + 16.0 * (fbm(x / 24.0, z / 24.0, 46, 3) - 0.5)
    # headlands keep their height past the coastline and plunge into the
    # sea ~40 m out, so there's no walkable strip around the cliff ends
    fade = smooth(clamp((z - (coast_z(x) - 40.0)) / 50.0, 0.0, 1.0))
  tall * smooth(clamp(cd / 16.0, 0.0, 1.0)) * fade

proc meadow_elev(x, z: float): float =
  1.6 + 3.2 * fbm(x / 41.0, z / 41.0, 70, 3)

const
  FALLS_X = -230.0 # base of the west cliff at the river head
  FALLS_Z = -55.0

proc falls_streak(z, y, phase_x: float): float =
  ## Curtain foam intensity in [0, 1]: static vertical foam lines (a
  ## per-column bias) plus random flecks and longer runs falling 16 m/s —
  ## 2 voxels per frame. The fleck grid wraps every P rows, and 24 frames x
  ## 2 voxels = 2 full wraps, so the loop is exact while staying genuinely
  ## random (integer drop per frame keeps features falling coherently).
  const P = 24
  let
    drop = if FRAMES > 0: 2.0 * P.float * sea_time / LOOP else: 0.0
    zi = int(floor(z)) * 31 + int(phase_x * 5.0)
    yw = ((int(floor(y + drop)) mod P) + P) mod P
    col = fbm(z * 1.1, 4.7, 94, 2) # which columns carry foam lines
    fleck = hash01(zi, yw div 2, 95) # short falling flecks
    run = hash01(zi * 7, yw div 6, 96) # longer falling runs
  if col > 0.60:
    result += 0.45
  elif col > 0.52:
    result += 0.2
  if fleck > 0.72:
    result += 0.35
  if run > 0.8:
    result += 0.3
  result = clamp(result, 0.0, 1.0)

# --- colors (demo_sea palette + rock) -------------------------------------------

proc quant(v: float32): float32 =
  round(v * 32.0) / 32.0

proc mix(a, b: Color, t: float): Color =
  let t = clamp(t, 0.0, 1.0)
  Color(
    r: quant(a.r + (b.r - a.r) * t),
    g: quant(a.g + (b.g - a.g) * t),
    b: quant(a.b + (b.b - a.b) * t),
    a: 1.0,
  )

let
  deep_water = col"082f66"
  mid_water = col"1565c0"
  crest_water = col"3f9be8"
  shallow_water = col"46c6b8"
  foam = col"f2f8fc"
  wet_sand = col"b39c6b"
  dry_sand = col"e8d9a6"
  low_grass = col"6fbf4e"
  high_grass = col"3e8a30"
  rock = col"7d6a55"
  trunk_col = col"6b4a2e"
  palm_col = col"2f7d32"
  rock_dark = col"46392c"
  rock_mid = col"6e5a41"
  rock_light = col"93805f"
  shade_grass = col"2e7226"
  charcoal = col"3d3630"
  birch = col"d9cbb0"
  conifer_green = col"235e2b"

let
  FLOWERS = [col"f2f2f2", col"e06060", col"ffd23d", col"a06de0"]
  PALM_GREENS = [col"2f7d32", col"3f9138", col"25702c"]
  LEAF_GREENS = [col"3c8f30", col"58a13c", col"2f7d32"]
  TRUNKS = [trunk_col, charcoal, birch]

# --- grids ----------------------------------------------------------------------

type ColKind = enum
  NONE
  LAND
  WATER

var
  kind_g = new_seq[ColKind](DIM * DIM)
  top = new_seq[int16](DIM * DIM)
  elev = new_seq[float32](DIM * DIM) # land: metres above sea level
  wave = new_seq[float32](DIM * DIM) # water: surface offset
  cliff = new_seq[float32](DIM * DIM) # land: cliff field height
  open_sea = new_seq[float32](DIM * DIM) # 0 = river, 1 = open water
  shore = new_seq[float32](DIM * DIM) # water: distance to nearest land

template idx(ix, iz: int): int =
  ix * DIM + iz

template wxf(ix: int): float =
  float(ix - G)

template wzf(iz: int): float =
  float(iz - G)

proc classify() =
  for ix in 0 ..< DIM:
    for iz in 0 ..< DIM:
      let
        x = wxf(ix)
        z = wzf(iz)
        i = idx(ix, iz)
        in_footprint = x >= X0 and x < X1 and z >= Z0 and z < Z1
        ie = island_elev(x, z)
      if ie > 0.05:
        kind_g[i] = LAND
        elev[i] = ie
        continue
      let
        c = coast_z(x)
        (rd, rt) = river_dist(x, z)
        rdw = rd + 4.0 * (fbm(x / 17.0, z / 17.0, 55, 3) - 0.5) * 2.0
      let cl = if in_footprint: cliff_elev(x, z) else: 0.0
      if rdw < river_halfwidth(rt):
        kind_g[i] = WATER
        open_sea[i] = clamp((c - z) / 35.0, 0.0, 1.0)
      elif cl > 2.0:
        # headlands extend into the sea as rock
        kind_g[i] = LAND
        cliff[i] = cl
        elev[i] = meadow_elev(x, z)
      elif z < c:
        kind_g[i] = WATER
        open_sea[i] = clamp((c - z) / 35.0, 0.0, 1.0)
      elif in_footprint:
        kind_g[i] = LAND
        cliff[i] = cl
        elev[i] = meadow_elev(x, z)

proc chamfer(target: ColKind, dist: var seq[float32]) =
  ## Distance in metres from every column to the nearest column of `target`.
  const BIG = 1e9'f32
  for i in 0 ..< DIM * DIM:
    dist[i] = if kind_g[i] == target: 0.0 else: BIG
  for ix in 0 ..< DIM:
    for iz in 0 ..< DIM:
      let i = idx(ix, iz)
      if ix > 0:
        dist[i] = min(dist[i], dist[idx(ix - 1, iz)] + 1.0)
        if iz > 0:
          dist[i] = min(dist[i], dist[idx(ix - 1, iz - 1)] + 1.41)
        if iz < DIM - 1:
          dist[i] = min(dist[i], dist[idx(ix - 1, iz + 1)] + 1.41)
      if iz > 0:
        dist[i] = min(dist[i], dist[idx(ix, iz - 1)] + 1.0)
  for ix in countdown(DIM - 1, 0):
    for iz in countdown(DIM - 1, 0):
      let i = idx(ix, iz)
      if ix < DIM - 1:
        dist[i] = min(dist[i], dist[idx(ix + 1, iz)] + 1.0)
        if iz > 0:
          dist[i] = min(dist[i], dist[idx(ix + 1, iz - 1)] + 1.41)
        if iz < DIM - 1:
          dist[i] = min(dist[i], dist[idx(ix + 1, iz + 1)] + 1.41)
      if iz < DIM - 1:
        dist[i] = min(dist[i], dist[idx(ix, iz + 1)] + 1.0)

proc fill_grids() =
  classify()
  chamfer(LAND, shore)
  var to_water = new_seq[float32](DIM * DIM)
  chamfer(WATER, to_water)
  for ix in 0 ..< DIM:
    for iz in 0 ..< DIM:
      let
        i = idx(ix, iz)
        x = wxf(ix)
        z = wzf(iz)
      case kind_g[i]
      of NONE:
        top[i] = 0
      of WATER:
        # calm river, full sea swell at the mouth; the river's texture is
        # painted (river_flow_streak), not sculpted
        let damp = 0.35 + 0.65 * open_sea[i]
        wave[i] = wave_height(x, z) * damp
        top[i] = int16(clamp(int(round(SEA_BASE + wave[i])), 0, 120))
        # (fill_water recomputes this per animation frame)
      of LAND:
        # beaches: meadow flattens toward any water; cliffs and the island
        # keep their own profiles (slot canyon walls stay vertical)
        let beach = 0.2 + max(to_water[i] - 1.0, 0.0) * 0.28
        var e = min(elev[i], beach)
        if island_elev(x, z) > 0.05:
          e = elev[i]
        e = max(e, cliff[i])
        elev[i] = e
        top[i] = int16(clamp(int(round(SEA_BASE + e)), 0, 120))

proc fill_water() =
  ## Recompute the wave field and water tops for the current sea_time; the
  ## land grids never change between frames.
  for ix in 0 ..< DIM:
    for iz in 0 ..< DIM:
      let i = idx(ix, iz)
      if kind_g[i] == WATER:
        let damp = 0.35 + 0.65 * open_sea[i]
        wave[i] = wave_height(wxf(ix), wzf(iz)) * damp
        top[i] = int16(clamp(int(round(SEA_BASE + wave[i])), 0, 120))

# --- emission --------------------------------------------------------------------

proc land_surface(ix, iz: int): Color =
  let
    i = idx(ix, iz)
    x = wxf(ix)
    z = wzf(iz)
    e = elev[i].float
    cl = cliff[i].float
  var slope = 0.0
  if ix > 0 and ix < DIM - 1:
    slope = max(slope, abs(elev[idx(ix + 1, iz)] - elev[idx(ix - 1, iz)]).float)
  if iz > 0 and iz < DIM - 1:
    slope = max(slope, abs(elev[idx(ix, iz + 1)] - elev[idx(ix, iz - 1)]).float)
  if cl > 3.0 and cl >= e - 0.01:
    # cliff: rock strata on the faces, grass wherever it flattens out
    # (plateau top, terrace ledges, headland tails)
    if slope < 1.4:
      let patch = fbm(x / 13.0, z / 13.0, 80, 3)
      return mix(low_grass, high_grass, clamp(e / CLIFF_H, 0.0, 1.0) * 0.7 + patch * 0.3)
    let strata = vnoise(e / 6.5, (x + z) / 90.0, 47)
    return mix(rock_dark, rock_light, clamp(e / CLIFF_H, 0.0, 1.0) * 0.55 + strata * 0.45)
  if e < 1.0:
    return mix(wet_sand, dry_sand, e / 1.0)
  if slope > 1.15 and e > 2.5:
    return mix(rock, high_grass, 0.15)
  let
    patch = fbm(x / 13.0, z / 13.0, 80, 3)
    alt = clamp((e - 1.0) / 8.0, 0.0, 1.0)
  result = mix(low_grass, high_grass, alt * 0.5 + patch * 0.5)
  # deep-green swathes and wildflower flecks keep the prairie lively
  let shade = fbm(x / 23.0, z / 23.0, 82, 3)
  if shade > 0.55:
    result = mix(result, shade_grass, (shade - 0.55) * 2.0)
  if e > 1.0 and hash01(ix, iz, 23) > 0.9955:
    result = FLOWERS[int(hash01(ix, iz, 24) * 3.999)]

proc water_surface(ix, iz: int): Color =
  let
    i = idx(ix, iz)
    x = wxf(ix)
    z = wzf(iz)
    h = wave[i].float
    e = -shore[i].float * 0.06 # shore-proximity analog of demo_sea's seabed
    s = open_sea[i].float
    # color from the un-damped wave: the calm river keeps the sea's full
    # crest/trough banding
    hc = h / (0.35 + 0.65 * s)
    t = clamp((hc + 1.0) / 2.0, 0.0, 1.0)
  result =
    if t < 0.5:
      mix(deep_water, mid_water, t / 0.5)
    else:
      mix(mid_water, crest_water, (t - 0.5) / 0.5)
  # the river runs deeper blue than the open sea
  result = mix(result, deep_water, 0.30 * (1.0 - s))
  # falls-style foam lines and dashes sliding downstream
  if s < 0.75:
    let fs = river_flow_streak(x, z)
    if fs > 0.0:
      result = mix(result, mix(crest_water, foam, 0.6), fs * 0.65 * (1.0 - s))
  let shallow = clamp(e + 1.0, 0.0, 1.0)
  if shallow > 0.0:
    result = mix(result, shallow_water, shallow * 0.85)
  # plunge pool: churned white below the falls (the churn field drifts in a
  # small circle so it animates and still loops)
  let pool = sqrt((x - FALLS_X - 4.0) ^ 2 + (z - FALLS_Z) ^ 2)
  if pool < 20.0:
    var
      chx = x
      chz = z
    if FRAMES > 0:
      let ph = 2.0 * PI * sea_time / LOOP
      chx = x + 2.2 * (cos(ph) - 1.0)
      chz = z + 2.2 * sin(ph)
    let churn = fbm(chx / 4.2, chz / 4.2, 92, 3)
    result = mix(result, foam, clamp(1.0 - pool / 20.0, 0.0, 1.0) * (0.4 + 0.6 * churn))
    # near-solid crash froth where the curtain meets the river
    if x > -238.0 and x < -229.0 and abs(z - FALLS_Z) < 11.0:
      result = mix(result, foam, 0.65 + 0.35 * churn)
  if e > -0.55:
    result = mix(result, foam, (e + 0.55) / 0.55 * 0.55)
  if e > -0.18:
    result = foam
  else:
    var grad = 0.0
    if ix > 0 and ix < DIM - 1:
      grad += abs(wave[idx(ix + 1, iz)] - wave[idx(ix - 1, iz)]).float
    if iz > 0 and iz < DIM - 1:
      grad += abs(wave[idx(ix, iz + 1)] - wave[idx(ix, iz - 1)]).float
    grad = grad / 2.0
    let breaking = open_sea[i] > 0.5
    if breaking and h > 0.32 and grad > 0.55 and fbm(x / 3.7, z / 3.7, 90, 3) > 0.52:
      result = mix(result, foam, 0.9)
    elif hash01(ix, iz, 11) > 0.9975 and h > 0.0:
      result = foam

# --- trees (shapes borrowed from world1's SpiralTree/OrbTree/CoralTree) ---------

proc stamp_ball(build: Build, ox, oz, cx, cy, cz, r: float, c: Color): int =
  let ir = int(ceil(r))
  for dx in -ir .. ir:
    for dy in -ir .. ir:
      for dz in -ir .. ir:
        if float(dx * dx + dy * dy + dz * dz) <= r * r + 0.4:
          build.draw(
            vec3(cx + dx.float - ox, cy + dy.float, cz + dz.float - oz), (KIND, c)
          )
          result.inc

proc stamp_disc(build: Build, ox, oz, cx, y, cz, r: float, c: Color): int =
  let ir = int(ceil(r))
  for dx in -ir .. ir:
    for dz in -ir .. ir:
      if float(dx * dx + dz * dz) <= r * r + 0.3:
        build.draw(vec3(cx + dx.float - ox, y, cz + dz.float - oz), (KIND, c))
        result.inc

proc tree_palm(
    build: Build, ox, oz, x, base, z: float, h: int, r1, r2: float, fcol: Color
): int =
  ## Palm with a gentle trunk curve, a frond crown that spreads with height,
  ## and the odd coconut.
  let
    lean_x = (r1 - 0.5) * 4.0
    lean_z = (r2 - 0.5) * 4.0
  var
    tx = x
    tz = z
  for i in 0 ..< h:
    let t = i.float / h.float
    tx = x + lean_x * t * t
    tz = z + lean_z * t * t
    build.draw(vec3(round(tx) - ox, base + i.float, round(tz) - oz), (KIND, trunk_col))
    result.inc
  let
    ty = base + h.float
    arms = 4 + int(r1 * 3.0)
    reach = 2 + int(h.float * 0.18 + r2 * 2.0) # taller palms spread wider
  build.draw(vec3(round(tx) - ox, ty + 1.0, round(tz) - oz), (KIND, fcol))
  result.inc
  for a in 0 ..< arms:
    let ang = a.float * (2.0 * PI / arms.float) + r2 * 0.8
    for s in 1 .. reach:
      let droop =
        if s <= reach div 2:
          0.0
        else:
          round(float(s - reach div 2) * 0.7)
      build.draw(
        vec3(
          round(tx + cos(ang) * s.float) - ox, ty - droop,
          round(tz + sin(ang) * s.float) - oz,
        ),
        (KIND, fcol),
      )
      result.inc
  if h >= 9 and r1 > 0.4: # coconuts
    build.draw(vec3(round(tx) + 1.0 - ox, ty - 1.0, round(tz) - oz), (KIND, trunk_col))
    build.draw(vec3(round(tx) - ox, ty - 1.0, round(tz) - 1.0 - oz), (KIND, trunk_col))
    result += 2

proc tree_broadleaf(
    build: Build, ox, oz, x, base, z: float, h: int, r1, r2, r3: float,
    tcol, lcol: Color,
): int =
  ## Straight trunk with a lumpy layered canopy.
  for i in 0 ..< h:
    result += stamp_disc(
      build, ox, oz, x, base + i.float, z, (if i < 2: 1.5 else: 0.9), tcol
    )
  let cr = 2.8 + h.float * 0.18 + r1 * 1.2
  result += stamp_ball(build, ox, oz, x, base + h.float + cr * 0.4, z, cr, lcol)
  result += stamp_ball(
    build, ox, oz, x + (r2 - 0.5) * 4.0, base + h.float, z + (r3 - 0.5) * 4.0,
    cr * 0.6, lcol,
  )
  result += stamp_ball(
    build, ox, oz, x - (r3 - 0.5) * 3.0, base + h.float + 1.0, z - (r2 - 0.5) * 3.0,
    cr * 0.5, lcol,
  )

proc tree_conifer(
    build: Build, ox, oz, x, base, z: float, h: int, r1: float, tcol: Color
): int =
  ## Tapered cone on a short trunk.
  for i in 0 ..< 2:
    build.draw(vec3(x - ox, base + i.float, z - oz), (KIND, tcol))
    result.inc
  let spread = 0.8 + r1 * 0.4
  for i in 0 ..< h:
    let r = max(0.6, float(h - i) * 0.32 * spread)
    result += stamp_disc(build, ox, oz, x, base + 2.0 + i.float, z, r, conifer_green)
  build.draw(vec3(x - ox, base + 2.0 + h.float, z - oz), (KIND, conifer_green))
  result.inc

proc low_neighbor(ix, iz: int): int =
  result = top[idx(ix, iz)].int
  for dx in -1 .. 1:
    for dz in -1 .. 1:
      let
        nx = ix + dx
        nz = iz + dz
      if nx >= 0 and nx < DIM and nz >= 0 and nz < DIM:
        result = min(result, top[idx(nx, nz)].int)

proc emit_land(build: Build, ix0, ix1: int): int =
  let
    ox = build.start_transform.origin.x
    oz = build.start_transform.origin.z
  build.buffer:
    for ix in ix0 ..< ix1:
      for iz in 0 ..< DIM:
        let i = idx(ix, iz)
        if kind_g[i] != LAND:
          continue
        let
          x = wxf(ix)
          z = wzf(iz)
          hi = top[i].int
          cl = cliff[i].float
        var lo = low_neighbor(ix, iz)
        if abs(x - ox) <= 2 and abs(z - oz) <= 2:
          lo = 0 # keep the unit's origin block buried
        if cl > 3.0:
          lo = 0 # cliffs are solid rock, not a hollow crust
        let surface = land_surface(ix, iz)
        for y in lo .. hi:
          let c =
            if y == hi:
              surface
            elif cl > 3.0:
              mix(rock_dark, rock_mid, vnoise(y.float / 5.0, (x - z) / 70.0, 48))
            else:
              mix(wet_sand, rock, 0.5)
          build.draw(vec3(x - ox, y.float, z - oz), (KIND, c))
          result.inc
        # dense small palms along the coasts and on the island
        let
          e = elev[i].float
          is_island = island_elev(x, z) > 0.05
          palm_bar = if is_island: 0.9968 else: 0.9987
          falls_clear = not (x < -200.0 and abs(z - FALLS_Z) < 20.0)
          # fronds must never reach the falls wedge — it's the one tall
          # water, and a shared position across two Things z-fights
        if cl < 3.0 and e > 1.0 and (is_island or e < 2.4) and falls_clear and
            hash01(ix, iz, 20) > palm_bar:
          result += tree_palm(
            build, ox, oz, x, float(hi + 1), z, 5 + int(hash01(ix, iz, 21) * 6.0),
            hash01(ix, iz, 22), hash01(ix, iz, 25),
            PALM_GREENS[int(hash01(ix, iz, 26) * 2.999)],
          )
        # inland trees on a jittered grid: one candidate spot per cell, so
        # they spread evenly without crowding. Mostly palms, with the odd
        # broadleaf or conifer for variety.
        const TCELL = 18
        let
          cx = ix div TCELL
          cz = iz div TCELL
          spot_x = cx * TCELL + int(hash01(cx, cz, 30) * (TCELL - 4).float) + 2
          spot_z = cz * TCELL + int(hash01(cx, cz, 31) * (TCELL - 4).float) + 2
        if ix == spot_x and iz == spot_z and cl < 3.0 and e > 1.0 and
            hash01(cx, cz, 32) < 0.22 and falls_clear and
            cliff_elev(x + 7.0, z) < 6.0 and cliff_elev(x - 7.0, z) < 6.0 and
            cliff_elev(x, z + 7.0) < 6.0 and cliff_elev(x, z - 7.0) < 6.0:
          let
            r1 = hash01(cx, cz, 33)
            r2 = hash01(cx, cz, 34)
            r3 = hash01(cx, cz, 35)
            kind_pick = hash01(cx, cz, 36)
            base = float(hi + 1)
          if kind_pick < 0.72:
            let h = 6 + int(r1 * 10.0) # 6..16
            result += tree_palm(
              build, ox, oz, x, base, z, h, r1, r2,
              PALM_GREENS[int(r3 * 2.999)],
            )
          elif kind_pick < 0.9:
            let h = 5 + int(r2 * 7.0) # 5..12
            result += tree_broadleaf(
              build, ox, oz, x, base, z, h, r1, r2, r3,
              TRUNKS[int(hash01(cx, cz, 37) * 1.999)], # brown or charcoal
              LEAF_GREENS[int(r1 * 2.999)],
            )
          else:
            let h = 8 + int(r3 * 10.0) # 8..18
            result += tree_conifer(build, ox, oz, x, base, z, h, r1, trunk_col)

proc emit_water(build: Build, ix0, ix1: int): int =
  let
    ox = build.start_transform.origin.x
    oz = build.start_transform.origin.z
  build.buffer:
    for ix in ix0 ..< ix1:
      for iz in 0 ..< DIM:
        let i = idx(ix, iz)
        if kind_g[i] != WATER:
          continue
        let
          x = wxf(ix)
          z = wzf(iz)
          hi = top[i].int
          lo = min(low_neighbor(ix, iz), 0) # always seal to the plane
          surface = water_surface(ix, iz)
        for y in lo .. hi:
          let c =
            if y == hi:
              surface
            elif y == hi - 1:
              mid_water
            else:
              deep_water
          build.draw(vec3(x - ox, y.float, z - oz), (KIND, c))
          result.inc
        # churning froth mounds at the curtain's base — raised foam voxels
        # that boil with the (looping) churn drift
        if x > -237.0 and x < -230.0 and abs(z - FALLS_Z) < 10.0:
          var
            fx = x
            fz = z
          if FRAMES > 0:
            let ph = 2.0 * PI * sea_time / LOOP
            fx = x + 2.2 * (cos(ph) - 1.0)
            fz = z + 2.2 * sin(ph)
          if fbm(fx / 3.1, fz / 3.1, 93, 3) > 0.5:
            build.draw(vec3(x - ox, float(hi + 1), z - oz), (KIND, foam))
            result.inc
        # waterfall on the west cliff at the river head: a solid streaked
        # wedge filling the notch from the curtain face back to the rock and
        # up to the (undulating) lip, so no angle can see behind it
        if x > FALLS_X - 7.5 and x <= FALLS_X - 6.5 and abs(z - FALLS_Z) < 10.0:
          var
            back = 0
            wall_top = 0
          for step in 1 .. 20:
            let nx = ix - step
            if nx < 0:
              break
            if kind_g[idx(nx, iz)] == LAND and top[idx(nx, iz)] > 25:
              back = step
              wall_top = top[idx(nx, iz)].int
              break
          if wall_top > 0:
            for bx in 0 ..< back:
              let bi = idx(ix - bx, iz)
              if kind_g[bi] != WATER:
                continue
              # rounded shoulder: the front of the lip arcs over instead of
              # ending in a square corner
              let ctop = wall_top - (if bx == 0: 2 elif bx == 1: 1 else: 0)
              for y in top[bi].int + 1 .. ctop:
                let streak = falls_streak(z, y.float, bx.float * 0.4)
                let c = mix(crest_water, foam, 0.2 + 0.7 * streak)
                build.draw(vec3(x - bx.float - ox, y.float, z - oz), (KIND, c))
                result.inc
            # chunky spray: heavy streaks bulge a voxel out of the face, so
            # the curtain has animated relief instead of a flat plane
            let front = idx(ix + 1, iz)
            if kind_g[front] == WATER:
              for y in top[front].int + 3 .. wall_top - 4:
                if falls_streak(z, y.float, -0.4) > 0.62:
                  build.draw(
                    vec3(x + 1.0 - ox, y.float, z - oz),
                    (KIND, mix(crest_water, foam, 0.8)),
                  )
                  result.inc

# --- main ------------------------------------------------------------------------

echo "connecting", (if ADDR == "": "" else: " to " & ADDR), "..."
Enu.connect(ADDR)
# terrain and water are adjacent at every shoreline; without this, draw's
# hand-placement join logic tries to merge them (and dereferences the game
# state a plain client doesn't have)
dont_join = true

echo "filling ", DIM, "x", DIM, " grids..."
fill_grids()

proc new_build(id: string, x, z: float, cull_down: bool): Build =
  result =
    if SAVE:
      Build.init(id = id, transform = Transform.init(vec3(x, 0.0, z)))
    else:
      Build.init(id = id & "_" & generate_id(), transform = Transform.init(vec3(x, 0.0, z)))
  if not SAVE:
    result.global_flags += EPHEMERAL
  result.end_asap()
  result.voxels.immediate = true
  Enu.things.add result
  result.cull_down_faces = cull_down
  Enu.client.tick

let
  # nobody culls down faces anymore: tree canopies and the falls' spray
  # bulges are both seen from below — and cull_down_faces isn't persisted,
  # so the shipped level never had the water cull anyway. If the frame-mesh
  # cache ever needs the savings back, the answer is the y==0-only engine
  # cull, not this flag.
  terrain = new_build("build_terrain", 0.0, 100.0, cull_down = false)
  water = new_build("build_water", 0.0, -400.0, cull_down = false)

var
  land_total = 0
  water_total = 0
const BAND = 50
for bx in countup(0, DIM - 1, BAND):
  let hi = min(bx + BAND, DIM)
  land_total += emit_land(terrain, bx, hi)
  water_total += emit_water(water, bx, hi)
  echo "band ", bx, "/", DIM, "  land=", land_total, " water=", water_total
  discard Enu.client.tick_until(PACE.seconds, false)

echo "TERRAIN=", terrain.id, " voxels=", land_total
echo "WATER=", water.id, " voxels=", water_total

if FRAMES > 0:
  # the static pass above IS frame 0 (sea_time = 0); redraw the water for
  # each later frame from a clean voxel state, demo_sea-style
  echo "generating ", FRAMES, " water frames over ", LOOP, "s..."
  for f in 0 ..< FRAMES:
    sea_time = LOOP * f.float / FRAMES.float
    if f > 0:
      water.voxels.clear(all = true)
      fill_water()
      var n = 0
      for bx in countup(0, DIM - 1, BAND):
        n += emit_water(water, bx, min(bx + BAND, DIM))
        discard Enu.client.tick_until(PACE.seconds, false)
    let index = water.save()
    echo "frame ", index, " saved"
    discard Enu.client.tick_until(FRAME_PACE.seconds, false)
  echo "settling..."
  discard Enu.client.tick_until(5.seconds, false)
  let fps = FRAMES.float / LOOP
  if SAVE:
    # persist playback as the unit's script (reload does not auto-play)
    water.code = Code.init("play(" & $fps & ")\n", runner = Enu.server_ctx_id)
    echo "water saved with a play(", fps, ") script — reload animates it"
  else:
    water.play(fps = fps)
    echo "water playing at ", fps, " fps"

if SAVE:
  echo "saving with the level — exit once fully visible in Enu"
else:
  echo "terrain is up — keeping it alive (kill me to reap it)"
Enu.client.every(1.second):
  discard
