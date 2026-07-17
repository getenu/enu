lock = true
show = false

# ----- spawn -----
# The course starts on the rise east of the waterfall. A fresh spawn lands
# at the world origin; carry them to the start. Reloads leave anyone who
# has already moved on alone.
if abs(player.position.x) < 5 and abs(player.position.z) < 5:
  # On a fresh boot the terrain streams in for a few seconds; teleporting
  # before the destination ground is meshed drops the player through the
  # floor. Wait until it reports solid.
  var tries = 0
  while floor_at(-219.0, -30.0) < 0 and tries < 60:
    sleep 0.5
    inc tries
  player.position = vec3(-219.5, 7.0, -30.5)
  player.rotation = -7.5

# ----- world locks -----
# The player edits exactly the exercise units; everything else is furniture.
let locked_ids = [
  "build_terrain", "build_water", "build_welcome_sign", "build_windmill",
  "build_maze", "build_lighthouse", "build_dock",
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

# ----- tool staging -----
# 0: nothing (walk to the sign) / 1: code tool (the whole mainland)
# 2: + block tools (boarding the boat) / 3: flight (finale reward)
var stage = -1

proc apply_stage(s: int) =
  if s == stage:
    return
  stage = s
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

var sign_read = false

forever:
  sleep 1

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

  let mainland_done =
    windmill_done and tower_done and maze_done and lighthouse_done

  # TODO(next wave): boat activation when mainland_done; ferry detection;
  # finale => stage 3.
  if not sign_read:
    apply_stage(0)
  elif not mainland_done:
    apply_stage(1)
  else:
    apply_stage(2)
