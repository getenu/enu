## Generates an ephemeral sea — swells, whitecaps, islands with beaches and
## palms — as one large scaled build. Stays alive to keep the unit; ctrl-c
## (or kill) reaps it. Iterate by editing the params below and re-running.
##
## Colors: the synced voxel format packs an ACTION_COLORS index, so only the
## six palette colors exist — anything else packs as ERASER and draws nothing.
## Shading is faked by hash-dithering palette colors (blue+black = depth,
## blue/white = crests and surf, brown+white = sand, green+black = grass).
##
## Env overrides: SEA_SCALE, SEA_SIZE (metres), SEA_X, SEA_Z.
import std/[math, os, strutils]
import client
import core, models/[builds, units, colors]

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
  let
    a = angle_deg * PI / 180.0
    k = 2.0 * PI / wavelength
  sin((x * cos(a) + z * sin(a)) * k + phase)

proc wave_height(x, z: float): float =
  ## Sea surface offset in metres, roughly [-1, 1].
  let groups = 0.4 + 0.6 * vnoise(x / 26.0, z / 26.0, 40)
  result = 0.42 * dir_wave(x, z, 43.0, 20.0, 0.0)
  result += 0.30 * dir_wave(x, z, 17.0, -35.0, 1.7)
  result += 0.20 * groups * dir_wave(x, z, 7.2, 65.0, 4.1)
  result += 0.18 * (fbm(x / 3.1, z / 3.1, 50, 3) - 0.5)

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

# --- colors: the 6 palette colors, shaded by dithering -------------------------

let
  blue = ACTION_COLORS[BLUE]
  white = ACTION_COLORS[WHITE]
  black = ACTION_COLORS[BLACK]
  brown = ACTION_COLORS[BROWN]
  green = ACTION_COLORS[GREEN]

proc pick(ix, iz: int, salt: uint32, a, b: Color, b_chance: float): Color =
  if hash01(ix, iz, salt) < b_chance: b else: a

# --- generation ----------------------------------------------------------------

Enu.client.connect
discard Enu.client.tick_until(3.seconds, Enu.client.connected)

let build = Build.init(CENTER_X, 0.0, CENTER_Z, save = false)
Enu.units.add build
build.scale = SCALE
Enu.client.tick

echo "generating ", DIM, "x", DIM, " sea..."

var
  wave = new_seq[float32](DIM * DIM) # sea surface, metres
  elev = new_seq[float32](DIM * DIM) # island elevation, metres vs sea level
  top = new_seq[int16](DIM * DIM) # column top, voxels
  land = new_seq[bool](DIM * DIM)

template idx(ix, iz: int): int =
  ix * DIM + iz

for ix in 0 ..< DIM:
  for iz in 0 ..< DIM:
    let
      mx = float(ix - HALF) * SCALE
      mz = float(iz - HALF) * SCALE
      e = island_elev(mx, mz)
      h = wave_height(mx, mz)
    wave[idx(ix, iz)] = h
    elev[idx(ix, iz)] = e
    if e > 0.05:
      land[idx(ix, iz)] = true
      top[idx(ix, iz)] = int16(clamp(int(round((SEA_BASE + e) / SCALE)), 0, 120))
    else:
      top[idx(ix, iz)] = int16(clamp(int(round((SEA_BASE + h) / SCALE)), 0, 120))

var voxels = 0
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
      # fill down to the lowest neighbour so slopes have no see-through gaps
      var lo = hi
      if ix > 0: lo = min(lo, top[idx(ix - 1, iz)].int)
      if ix < DIM - 1: lo = min(lo, top[idx(ix + 1, iz)].int)
      if iz > 0: lo = min(lo, top[idx(ix, iz - 1)].int)
      if iz < DIM - 1: lo = min(lo, top[idx(ix, iz + 1)].int)

      var surface: Color
      if land[i]:
        if e < 0.35:
          surface = pick(ix, iz, 3, brown, black, 0.2) # wet sand
        elif e < 1.0:
          surface = pick(ix, iz, 3, brown, white, 0.3) # dry beach sparkle
        else:
          var slope = 0.0
          if ix > 0 and ix < DIM - 1:
            slope = max(slope, abs(elev[idx(ix + 1, iz)] - elev[idx(ix - 1, iz)]).float)
          if iz > 0 and iz < DIM - 1:
            slope = max(slope, abs(elev[idx(ix, iz + 1)] - elev[idx(ix, iz - 1)]).float)
          if slope > 1.15 and e > 2.5:
            surface = pick(ix, iz, 5, brown, black, 0.45) # rock face
          else:
            # grass, textured with dark patches following the fbm
            let patch = fbm(mx / 13.0, mz / 13.0, 80, 3)
            if patch < 0.38:
              surface = pick(ix, iz, 6, green, black, 0.25)
            else:
              surface = pick(ix, iz, 6, green, black, 0.06)
      else:
        # water: blue, dithered darker in troughs, white toward crests + shore
        let t = clamp((h + 1.0) / 2.0, 0.0, 1.0)
        if t < 0.3:
          surface = pick(ix, iz, 7, blue, black, (0.3 - t) / 0.3 * 0.5)
        elif t > 0.62:
          surface = pick(ix, iz, 7, blue, white, (t - 0.62) * 0.5)
        else:
          surface = blue
        # churned surf building toward the shoreline
        if e > -0.55:
          let surf = clamp((e + 0.55) / 0.55, 0.0, 1.0)
          surface = pick(ix, iz, 8, surface, white, surf * 0.6)
        # shoreline foam ring
        if e > -0.18:
          surface = white
        else:
          # whitecaps: steep crests, broken up by noise
          var grad = 0.0
          if ix > 0 and ix < DIM - 1:
            grad += abs(wave[idx(ix + 1, iz)] - wave[idx(ix - 1, iz)]).float
          if iz > 0 and iz < DIM - 1:
            grad += abs(wave[idx(ix, iz + 1)] - wave[idx(ix, iz - 1)]).float
          grad = grad / (2.0 * SCALE)
          if h > 0.32 and grad > 0.55 and fbm(mx / 3.7, mz / 3.7, 90, 3) > 0.52:
            surface = white
          elif hash01(ix, iz, 11) > 0.9975 and h > 0.0:
            surface = white # lone flecks

      for y in lo .. hi:
        let c =
          if y == hi:
            surface
          elif land[i]:
            brown
          elif y == hi - 1:
            blue
          else:
            black # unlit depths under the surface
        build.draw(
          vec3(float(ix - HALF), float(y), float(iz - HALF)), (COMPUTED, c)
        )
        voxels.inc

  # palms on the grass
  var palms = 0
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
          build.draw(vec3(px, float(base + y), pz), (COMPUTED, brown))
        let ty = float(base + tall)
        for (dx, dy, dz) in [
          (0, 1, 0), (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1),
          (2, 0, 0), (-2, 0, 0), (0, 0, 2), (0, 0, -2),
          (2, -1, 0), (-2, -1, 0), (0, -1, 2), (0, -1, -2),
        ]:
          build.draw(
            vec3(px + dx.float, ty + dy.float, pz + dz.float),
            (COMPUTED, green),
          )
        voxels += tall + 13
        palms.inc

  echo "palms: ", palms

echo "BUILD=", build.id, " voxels=", voxels
echo "sea is up — keeping it alive (kill me to reap it)"
Enu.client.every(1.second):
  discard
