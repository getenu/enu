show = false
lock = true

# Bootstrap: loads near the front of the level so the player is positioned
# and interactive within a second or two, while the rest of the units keep
# streaming in behind them. A fresh spawn lands at the world origin; carry
# them to the course start by the waterfall. Reloads (player already moved)
# skip the carry.
if abs(player.position.x) < 5 and abs(player.position.z) < 5:
  var tries = 0
  while floor_at(-219.0, -30.0) < 0 and tries < 100:
    sleep 0.1
    inc tries
  player.position = vec3(-219.5, 7.0, -30.5)
  player.rotation = -7.5

# Hand control to the player now — no need to wait for the whole level.
player.spawning = false

# Collision meshes lag the voxel data, so a just-teleported player can sink
# through the still-forming hill. Catch that for a few seconds — but only
# near the spawn, so it never fights a player who has already walked off.
var guard = 0
while guard < 25:
  sleep 0.2
  let ground = floor_at(-219.0, -30.0).float
  if (player.position - vec3(-219.5, 0.0, -30.5)).length < 6 and
      ground > 0 and player.position.y < ground - 1.0:
    player.position = vec3(-219.5, ground + 1.0, -30.5)
  inc guard
