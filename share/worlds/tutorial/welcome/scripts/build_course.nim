lock = true
show = false

# (spawn/positioning moved to build_bootstrap, which loads early so the
# player is placed and interactive while the rest of the level streams in)

# ----- world locks -----
# The player edits exactly the exercise units; everything else is furniture.
let locked_ids = [
  "build_terrain", "build_water", "build_welcome_sign", "build_windmill",
  "build_maze", "build_lighthouse", "build_dock", "build_boat",
  "build_tower_plot", "build_isle_pad", "build_peninsula_pad",
  "build_launcher", "build_cottage", "build_firework_stand",
  "build_summit_gate", "build_fisher_hut",
]
for b in all_builds():
  for id in locked_ids:
    if b.id == id:
      b.lock = true

# ----- progress beacons -----
# Root units at each site; kicking a beacon's glow above 0.05 tells it to
# light up (it takes over its own pulsing from there).
proc light_beacon(id: string) =
  let beacon = Build(find_by_id(id))
  if ?beacon:
    beacon.glow = 0.2

# ----- completion detection -----
# Everything is re-derived from live world state, so progress survives
# reloads for free: the player's fixes re-run and re-prove themselves.
var
  windmill_done = false
  tower_done = false
  maze_done = false
  lighthouse_done = false
  ferry_done = false
  cottage_done = false
  fireworks_done = false
  windmill_total = 0.0
  windmill_prev = float.high

proc angle_delta(a, b: float): float =
  result = abs(a - b)
  if result > 180:
    result = 360 - result

proc check_windmill(): bool =
  # blades ref is re-looked-up every poll: the unit reloads every time the
  # player edits its script, and old refs go stale.
  let blades = Build(find_by_id("build_windmill_blades"))
  if not ?blades:
    return false
  let rot = blades.rotation
  if windmill_prev != float.high:
    windmill_total += angle_delta(rot, windmill_prev)
  windmill_prev = rot
  windmill_total >= 355

proc check_tower(): bool =
  let site = Build(find_by_id("build_tower_site"))
  if not ?site:
    return false
  site.bounds.max.y - 3.0 >= 12

proc check_maze(): bool =
  let runner = Bot(find_by_id("bot_maze_runner"))
  if not ?runner:
    return false
  let exit_center = vec3(-36.0, 6.0, -13.0)
  (runner.position - exit_center).length < 2.5

proc check_lighthouse(): bool =
  let lamp = Build(find_by_id("build_lighthouse_lamp"))
  if not ?lamp:
    return false
  lamp.glow > 0.5

proc check_ferry(): bool =
  # castaways delivered to the peninsula camp
  var delivered = 0
  for id in ["bot_castaway_1", "bot_castaway_2", "bot_castaway_3"]:
    let castaway = Bot(find_by_id(id))
    if ?castaway:
      let p = castaway.position
      if p.x > 60 and p.x < 150 and p.z > -150 and p.z < -108 and p.y > 1:
        inc delivered
  delivered >= 2

# E6/E7 constants derived from the shipped north-mainland builds: the cottage's
# storm breach is the east-wall core (local x8, y1..4, z2..4); the fireworks rack
# top is the shell unit's origin y.
let north_wired = true
let rack_top = 7.0

proc check_cottage(): bool =
  # Derive the breach box from the cottage's live origin, so it tracks the build
  # if it's moved (it rests on the terrain, whose height can shift it).
  let cottage = find_by_id("build_cottage")
  if not ?cottage:
    return false
  let o = cottage.position
  north_wired and not clear_box(
    o.x + 8.0, o.y + 1.0, o.z + 2.0,
    o.x + 8.0, o.y + 4.0, o.z + 4.0,
  )

proc check_fireworks(): bool =
  if not north_wired:
    return false
  let shells = Build(find_by_id("build_fireworks"))
  if not ?shells:
    return false
  shells.bounds.max.y >= rack_top + 8

# ----- rat-foundation wall monitor (moved off the exercise unit) -----
# The invisible-rats side quest reports its state through build_rat_foundation's
# pen colour — green (building), blue (walls up), red (walls hidden) — which the
# rat-catcher and the rocket read. We drive it here so the exercise unit itself
# stays clean. Counts WHITE/INVISIBLE blocks at wall height across the footprint
# in world coords, so whatever unit the player builds the walls on still counts.
proc update_rat_walls() =
  let f = find_by_id("build_rat_foundation")
  if not ?f:
    return
  let o = f.position
  var white_n = 0
  var invis_n = 0
  for x in 0 .. 10:
    for z in 0 .. 12:
      let c = block_color_at(vec3(o.x + x.float, o.y + 2.0, o.z + z.float))
      if c == white:
        inc white_n
      elif c == invisible:
        inc invis_n
  if invis_n >= 15:
    Build(f).color = red
  elif white_n >= 15:
    Build(f).color = blue
  else:
    Build(f).color = green

# ----- tool staging -----
# 0: nothing (walk to the sign) / 1: code tool (the whole mainland)
# 2: + block tools (mainland done) / 3: flight (finale reward)
# Gating is OFF until final acceptance testing (user call): everyone gets
# the full toolbar and flight; detection and beacons keep running so the
# course can still be reviewed end to end.
const ENFORCE_PROGRESSION = false
var stage = -1

proc apply_stage(s: int) =
  if s == stage:
    return
  stage = s
  if not ENFORCE_PROGRESSION:
    player.tools = {
      CodeMode, BlueBlock, RedBlock, GreenBlock, BlackBlock, WhiteBlock,
      BrownBlock, PlaceBot,
    }
    player.can_fly = true
    return
  if s == 0:
    player.tools = {}
  elif s == 1:
    player.tools = {CodeMode}
  elif s >= 2:
    player.tools = {
      CodeMode, BlueBlock, RedBlock, GreenBlock, BlackBlock, WhiteBlock,
      BrownBlock,
    }
  player.can_fly = s >= 3

# ----- live progress on the standalone progress sign -----
# The tall progress board sits off to the player's right. We keep its in-world
# message in sync with world state, reading its say-sign straight off the build
# (`board.sign`) so it survives the board being moved or hot-reloaded. (The
# welcome sign owns its own page now — we don't touch it.)

proc mark(done: bool): string =
  if done: "[x]" else: "[ ]"

# The always-on board face: a tight checklist, no title (the board is obviously
# the objectives) so the text can ride bigger.
proc checklist(): string =
  \"""
**Mainland**

- {mark(windmill_done)} Windmill blades turning
- {mark(tower_done)} Lookout tower raised
- {mark(maze_done)} Maze bot at its exit
- {mark(lighthouse_done)} Lighthouse lit

**The isle**

- {mark(ferry_done)} Castaways ferried
- {mark(cottage_done)} Cottage patched
- {mark(fireworks_done)} Fireworks woken
"""

proc done_count(): int =
  for d in [windmill_done, tower_done, maze_done, lighthouse_done, ferry_done,
      cottage_done, fireworks_done]:
    if d:
      inc result

# The click-to-open panel: same checklist, expanded with a line of orientation
# per task (where to go / what it needs, not the answer) and the one non-obvious
# rule — the isle only opens once the four mainland beacons are lit.
proc detail(): string =
  \"""
# Progress: {done_count()} of 7

Every bot on the island is stuck on something. Wander over, hear them out, and
lend a hand — most of it is just a few lines of code.

**Mainland**

- {mark(windmill_done)} **Windmill blades turning** — the miller's mill won't
  spin. Make its blades turn, over and over.
- {mark(tower_done)} **Lookout tower raised** — the builder's ring is only two
  courses tall. Take it up to twelve.
- {mark(maze_done)} **Maze bot at its exit** — the little bot needs the whole
  route through the hedge, step by step.
- {mark(lighthouse_done)} **Lighthouse lit** — the lamp is a cold lump of iron.
  Bring it back to life.

Light all four and the ferry wakes at the dock — climb aboard to reach the isle.

**The isle**

- {mark(ferry_done)} **Castaways ferried** — sail the stranded folk across.
- {mark(cottage_done)} **Cottage patched** — a storm tore a hole in the east
  wall. Fill it back in.
- {mark(fireworks_done)} **Fireworks woken** — the shell on the rack is a dud.
  Make it fly.
"""

var sign_read = false

forever:
  sleep 1

  # fresh-boot safety: collision meshes can lag the spawn carry by more
  # than the settle window on a heavy boot — anyone buried at the spawn
  # hill gets lifted back on top, whenever it happens.
  if abs(player.position.x + 219.5) < 4 and abs(player.position.z + 30.5) < 4:
    let ground = floor_at(-219.0, -30.0).float
    if ground > 0 and player.position.y < ground - 0.5:
      player.position = vec3(-219.5, ground + 2.0, -30.5)

  if not sign_read and ?player.open_sign and
      (player.position - vec3(-215.0, 3.0, -37.0)).length < 10:
    sign_read = true

  if not windmill_done and check_windmill():
    windmill_done = true
    light_beacon("build_beacon_windmill")
  if not tower_done and check_tower():
    tower_done = true
    light_beacon("build_beacon_tower")
  if not maze_done and check_maze():
    maze_done = true
    light_beacon("build_beacon_maze")
  if not lighthouse_done and check_lighthouse():
    lighthouse_done = true
    light_beacon("build_beacon_lighthouse")
  if not ferry_done and check_ferry():
    ferry_done = true
    light_beacon("build_beacon_ferry")
  if not cottage_done and check_cottage():
    cottage_done = true
  if not fireworks_done and check_fireworks():
    fireworks_done = true

  update_rat_walls()

  let mainland_done =
    windmill_done and tower_done and maze_done and lighthouse_done
  let finale_done = cottage_done and fireworks_done

  if finale_done:
    light_beacon("build_beacon_finale")

  if not sign_read:
    apply_stage(0)
  elif not mainland_done:
    apply_stage(1)
  elif not finale_done:
    apply_stage(2)
  else:
    apply_stage(3)

  let board = find_by_id("build_progress_sign")
  if ?board and ?board.sign:
    let page = checklist()
    if board.sign.message != page:
      board.sign.message = page
    let more = detail()
    if board.sign.more != more:
      board.sign.more = more
