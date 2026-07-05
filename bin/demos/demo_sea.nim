## Generates an ephemeral sea — swells, whitecaps, islands with beaches and
## palms — as one large scaled build. Stays alive to keep the unit; ctrl-c
## (or kill) reaps it. Iterate by editing the params below and re-running.
##
## Colors: named palette colors stay env-remappable; every other RGB value
## becomes a static palette entry, so shading here uses true gradients.
##
## Env overrides: SEA_SCALE, SEA_SIZE (metres), SEA_X, SEA_Z, and SEA_TIME
## (seconds) — the sea is a pure function of position and time, so advancing
## SEA_TIME renders successive frames of the same animated ocean.
import std/[math, os, strutils]
import client
import core, models/[builds, units, colors, voxels]

proc env_f(name: string, default: float): float =
  let v = get_env(name)
  if v == "": default else: v.parse_float

let
  SCALE = env_f("SEA_SCALE", 0.5) # metres per voxel
  SIZE_M = env_f("SEA_SIZE", 250.0) # square side, metres
  DIM = int(SIZE_M / SCALE) # voxel columns per side
  HALF = DIM div 2
  CENTER_X = env_f("SEA_X", -300.0)
  CENTER_Z = env_f("SEA_Z", -40.0)
  FRAMES = int(env_f("SEA_FRAMES", 0)) # >0: flipbook of N frames over LOOP
  LOOP = env_f("SEA_LOOP", 4.0) # seconds per animation loop (flipbook mode)

var sea_time = env_f("SEA_TIME", 0.0) # seconds; waves travel, foam follows

const
  SEA_BASE = 1.1 # mean sea surface height, metres above ground
  SEED = 7'u32

# --- deterministic noise ----------------------------------------------------

proc hash01(ix, iz: int, salt: uint32): float =
  var h = cast[uint32](ix) * 0x85ebca6b'u32 xor
    cast[uint32](iz) * 0xc2b2ae35'u32 xor (salt * 0x9e3779b9'u32 + SEED)
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

# --- waves -------------------------------------------------------------------

proc dir_wave(x, z, wavelength, angle_deg, phase: float): float =
  ## A plane wave travelling along `angle_deg`, using deep-water dispersion
  ## (c = sqrt(g * wavelength / 2pi)) so long swell outruns the chop. In
  ## flipbook mode each speed is snapped a few percent so the wave completes
  ## whole cycles in LOOP seconds — frame N-1 wraps seamlessly to frame 0.
  let
    a = angle_deg * PI / 180.0
    k = 2.0 * PI / wavelength
  var speed = sqrt(9.81 * wavelength / (2.0 * PI))
  if FRAMES > 0:
    let cycles = max(1.0, round(speed * LOOP / wavelength))
    speed = cycles * wavelength / LOOP
  sin((x * cos(a) + z * sin(a)) * k - k * speed * sea_time + phase)

proc wave_height(x, z: float): float =
  ## Sea surface offset in metres, roughly [-1, 1].
  # groups and ripple drift with a slow "wind" so foam animates too; the
  # flipbook drifts in a small circle so the noise fields loop with LOOP
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

# --- islands ------------------------------------------------------------------

type Island = tuple[cx, cz, r, tall: float]

const ISLANDS: array[5, Island] = [
  (-40.0, 35.0, 52.0, 9.5), # main island, south-west of centre
  (55.0, -60.0, 26.0, 4.5),
  (-15.0, -90.0, 14.0, 2.8),
  (80.0, 40.0, 11.0, 2.2),
  (30.0, 95.0, 18.0, 1.0), # sandbar, barely above water
]

proc island_elev(x, z: float): float =
  ## Metres above (positive) or below (negative, capped) sea level.
  result = -2.0
  for isl in ISLANDS:
    let
      dx = x - isl.cx
      dz = z - isl.cz
      d = sqrt(dx * dx + dz * dz)
      # ragged coastline: wobble the radius with positional fbm
      wobble = 0.7 + 0.6 * fbm(x / 45.0 + isl.cx, z / 45.0 + isl.cz, 60, 3)
      rr = isl.r * wobble
      t = 1.0 - d / rr
    if t > -0.6:
      let e =
        if t > 0:
          isl.tall * pow(t, 1.6) + 1.5 * t * (fbm(x / 9.0, z / 9.0, 70, 3) - 0.4)
        else:
          # underwater skirt, for shallow-water shading
          t * 3.0
      result = max(result, e)

# --- colors: true gradients ----------------------------------------------------

proc quant(v: float32): float32 =
  ## Quantize to 1/32 steps: gradients stay visually smooth while the
  ## distinct-color count (and so the build's static palette) stays small.
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

# --- generation ----------------------------------------------------------------

Enu.client.connect
discard Enu.client.tick_until(3.seconds, Enu.client.connected)
# connected != synced: wait for the root collection before adding units
discard Enu.client.tick_until(10.seconds, "root_units" in Enu.client.ctx)

var
  wave = new_seq[float32](DIM * DIM) # sea surface, metres
  elev = new_seq[float32](DIM * DIM) # island elevation, metres vs sea level
  top = new_seq[int16](DIM * DIM) # column top, voxels
  land = new_seq[bool](DIM * DIM)
  elev_ready = false

template idx(ix, iz: int): int =
  ix * DIM + iz

proc fill_grids() =
  ## Wave-dependent grids for the current `sea_time`. The island field is
  ## time-independent and computed once.
  for ix in 0 ..< DIM:
    for iz in 0 ..< DIM:
      let
        mx = float(ix - HALF) * SCALE
        mz = float(iz - HALF) * SCALE
      if not elev_ready:
        let e = island_elev(mx, mz)
        elev[idx(ix, iz)] = e
        land[idx(ix, iz)] = e > 0.05
      let h = wave_height(mx, mz)
      wave[idx(ix, iz)] = h
      if land[idx(ix, iz)]:
        top[idx(ix, iz)] =
          int16(clamp(int(round((SEA_BASE + elev[idx(ix, iz)]) / SCALE)), 0, 120))
      else:
        top[idx(ix, iz)] = int16(clamp(int(round((SEA_BASE + h) / SCALE)), 0, 120))
  elev_ready = true

proc draw_sea(build: Build): int =
  build.buffer:
    for ix in 0 ..< DIM:
      for iz in 0 ..< DIM:
        let
          i = idx(ix, iz)
          mx = float(ix - HALF) * SCALE
          mz = float(iz - HALF) * SCALE
          h = wave[i].float
          e = elev[i].float
          hi = top[i].int
        # fill down to the lowest neighbour (diagonals included) so slopes
        # have no see-through gaps, even corner-to-corner
        var lo = hi
        for dx in -1 .. 1:
          for dz in -1 .. 1:
            let nx = ix + dx
            let nz = iz + dz
            if nx >= 0 and nx < DIM and nz >= 0 and nz < DIM:
              lo = min(lo, top[idx(nx, nz)].int)

        var surface: Color
        if land[i]:
          if e < 1.0:
            surface = mix(wet_sand, dry_sand, e / 1.0)
          else:
            var slope = 0.0
            if ix > 0 and ix < DIM - 1:
              slope = max(slope, abs(elev[idx(ix + 1, iz)] - elev[idx(ix - 1, iz)]).float)
            if iz > 0 and iz < DIM - 1:
              slope = max(slope, abs(elev[idx(ix, iz + 1)] - elev[idx(ix, iz - 1)]).float)
            if slope > 1.15 and e > 2.5:
              surface = mix(rock, high_grass, 0.15)
            else:
              # grass: darker with altitude, mottled by the fbm patches
              let patch = fbm(mx / 13.0, mz / 13.0, 80, 3)
              let alt = clamp((e - 1.0) / 8.0, 0.0, 1.0)
              surface = mix(low_grass, high_grass, alt * 0.6 + patch * 0.4)
        else:
          # water: depth-graded blues, turquoise shallows, foam at the shore
          let t = clamp((h + 1.0) / 2.0, 0.0, 1.0)
          surface =
            if t < 0.5:
              mix(deep_water, mid_water, t / 0.5)
            else:
              mix(mid_water, crest_water, (t - 0.5) / 0.5)
          let shallow = clamp(e + 1.0, 0.0, 1.0)
          if shallow > 0.0:
            surface = mix(surface, shallow_water, shallow * 0.85)
          # churned surf building toward the shoreline
          if e > -0.55:
            surface = mix(surface, foam, (e + 0.55) / 0.55 * 0.55)
          # shoreline foam ring
          if e > -0.18:
            surface = foam
          else:
            # whitecaps: steep crests, broken up by noise
            var grad = 0.0
            if ix > 0 and ix < DIM - 1:
              grad += abs(wave[idx(ix + 1, iz)] - wave[idx(ix - 1, iz)]).float
            if iz > 0 and iz < DIM - 1:
              grad += abs(wave[idx(ix, iz + 1)] - wave[idx(ix, iz - 1)]).float
            grad = grad / (2.0 * SCALE)
            if h > 0.32 and grad > 0.55 and fbm(mx / 3.7, mz / 3.7, 90, 3) > 0.52:
              surface = mix(surface, foam, 0.9)
            elif hash01(ix, iz, 11) > 0.9975 and h > 0.0:
              surface = foam # lone flecks

        for y in lo .. hi:
          let c =
            if y == hi:
              surface
            elif land[i]:
              mix(wet_sand, rock, 0.5)
            elif y == hi - 1:
              mid_water
            else:
              deep_water # depths under the surface
          build.draw(
            vec3(float(ix - HALF), float(y), float(iz - HALF)), (COMPUTED, c)
          )
          result.inc

    # palms on the grass
    for ix in 6 ..< DIM - 6:
      for iz in 6 ..< DIM - 6:
        let i = idx(ix, iz)
        if land[i] and elev[i] > 1.4 and hash01(ix, iz, 20) > 0.9985:
          let
            base = top[i].int
            tall = 8 + int(hash01(ix, iz, 21) * 5.0)
            px = float(ix - HALF)
            pz = float(iz - HALF)
          for y in 1 .. tall:
            build.draw(vec3(px, float(base + y), pz), (COMPUTED, trunk_col))
          let ty = float(base + tall)
          for (dx, dy, dz) in [
            (0, 1, 0), (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1),
            (2, 0, 0), (-2, 0, 0), (0, 0, 2), (0, 0, -2),
            (2, -1, 0), (-2, -1, 0), (0, -1, 2), (0, -1, -2),
          ]:
            build.draw(
              vec3(px + dx.float, ty + dy.float, pz + dz.float),
              (COMPUTED, palm_col),
            )
          result += tall + 13

proc new_sea_build(): Build =
  result = Build.init(CENTER_X, 0.0, CENTER_Z, save = false)
  Enu.units.add result
  result.scale = SCALE
  Enu.client.tick

if FRAMES == 0:
  echo "generating ", DIM, "x", DIM, " sea..."
  let build = new_sea_build()
  fill_grids()
  let voxels = draw_sea(build)
  echo "BUILD=", build.id, " voxels=", voxels
  echo "sea is up — keeping it alive (kill me to reap it)"
  Enu.client.every(1.second):
    discard
else:
  echo "generating ", FRAMES, " frames of ", DIM, "x", DIM, " sea..."
  let build = new_sea_build()
  for f in 0 ..< FRAMES:
    sea_time = LOOP * f.float / FRAMES.float
    if f > 0:
      build.voxels.clear()
    fill_grids()
    let voxels = draw_sea(build)
    let index = build.save_frame()
    echo "frame ", index, ": ", voxels, " voxels"
    # pace the flood: keep ticking so each frame's chunks drain before the
    # next burst — a sustained blast drops the session
    discard Enu.client.tick_until(2.seconds, false)

  echo "settling..."
  discard Enu.client.tick_until(5.seconds, false)
  if get_env("SEA_HOLD") != "":
    # debug mode: hold frame 0 for 30s, then frame 4 — no playback
    build.current_frame = 0
    echo "BUILD=", build.id, " holding frame 0"
    var flipped = false
    var ticks = 0
    Enu.client.every(1.second):
      inc ticks
      if ticks == 30 and not flipped:
        flipped = true
        build.current_frame = 4
        echo "holding frame 4"
  else:
    let fps = FRAMES.float / LOOP
    build.play_frames(fps = fps)
    echo "BUILD=", build.id, " playing ", FRAMES, " frames at ", fps,
      "fps — kill me to reap it"
    Enu.client.every(1.second):
      discard
