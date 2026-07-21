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
  "build_launcher", "build_cottage_shell", "build_firework_stand",
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

# E6/E7 constants derived from the shipped north-mainland builds: the
# cottage's storm breach is the east-wall core (local x8, z2..4, y1..4 on
# origin (40,4,-131)); the fireworks rack top is the shell unit's origin y.
let north_wired = true
let breach_min = vec3(48.0, 5.0, -129.0)
let breach_max = vec3(48.0, 8.0, -127.0)
let rack_top = 7.0

proc check_cottage(): bool =
  north_wired and
    not clear_box(
      breach_min.x, breach_min.y, breach_min.z, breach_max.x, breach_max.y,
      breach_max.z,
    )

proc check_fireworks(): bool =
  if not north_wired:
    return false
  let shells = Build(find_by_id("build_fireworks"))
  if not ?shells:
    return false
  shells.bounds.max.y >= rack_top + 8

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
# The tall progress board sits off to the player's right; its say-sign hangs
# near (-207, 27, -32.5). We keep its in-world message in sync with world state.
# (The welcome sign owns its own page now — we don't touch it.) The sign loads
# after us, so the scan below runs in the loop until it resolves.
var progress_sign: Sign

proc mark(done: bool): string =
  if done: "[x]" else: "[ ]"

proc checklist(): string =
  \"""
# Objectives

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

var last_page = ""
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

  if progress_sign.is_nil:
    for s in all_signs():
      if (s.position - vec3(-207.0, 27.0, -32.5)).length < 10:
        progress_sign = s
  if ?progress_sign:
    let page = checklist()
    if page != last_page:
      last_page = page
      progress_sign.message = page
