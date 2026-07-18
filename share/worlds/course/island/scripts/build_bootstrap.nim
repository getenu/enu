show = false
lock = true

# Bootstrap: loads right after the terrain (load_order index 1) so the player is
# positioned while the rest of the level streams in behind them. A fresh spawn
# lands at the world origin; carry them to the course start by the waterfall.
# Reloads (player already moved) skip the carry.
if abs(player.position.x) < 5 and abs(player.position.z) < 5:
  var tries = 0
  while floor_at(-219.0, -30.0) < 0 and tries < 100:
    sleep 0.1
    inc tries
  player.position = vec3(-219.5, 7.0, -30.5)
  player.rotation = -7.5

# Let the framed waterfall view settle, then drop the loading splash and hand
# control over. (The splash is up for the whole load anyway; these sleeps are
# starved of VM ticks while the level loads, so in practice the reveal lands
# near load-end — by which point the view has meshed and the player has settled
# onto the ground, which is what we want to show.)
sleep 0.4
player.clear_load_screen()
player.spawning = false

# Collision meshes lag the voxel data, so a just-teleported player can sink into
# the still-forming hill and wedge there (stuck until they fly out). Catch it for
# a few seconds — but only near the spawn, so it never fights a player who has
# already walked off. `ground + 1` is roughly where the capsule rests on the
# surface; below that is a sink, so lift them clear.
var guard = 0
while guard < 25:
  sleep 0.2
  let ground = floor_at(-219.0, -30.0).float
  if (player.position - vec3(-219.5, 0.0, -30.5)).length < 6 and
      ground > 0 and player.position.y < ground + 1.0:
    player.position = vec3(-219.5, ground + 2.0, -30.5)
  inc guard
