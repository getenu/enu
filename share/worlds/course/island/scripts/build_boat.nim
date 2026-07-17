lock = true
speed = 0

# The ferry to the little island. Sleeps at the dock until all four
# mainland beacons are lit (read directly off their glow — the director
# kicks them as exercises complete), then hoists sail and carries anyone
# who steps aboard across the strait, and back again.

# ----- hull -----
# origin sits at the waterline center of the hull; the deck lands at
# world y 3 to match the dock's T-head planks.
box(vec3(-2, 0, -4), vec3(1, 1, 3), color = brown) # hull block
box(vec3(-2, 2, -4), vec3(1, 2, -4), color = brown) # stern gunwale
box(vec3(-2, 2, 3), vec3(1, 2, 3), color = brown) # bow gunwale
box(vec3(-2, 2, -4), vec3(-2, 2, 3), color = brown) # port gunwale
box(vec3(1, 2, -4), vec3(1, 2, 3), color = brown) # starboard gunwale
# mast
box(vec3(0, 2, 0), vec3(0, 7, 0), color = black)

proc hoist_sail() =
  box(vec3(0, 3, 1), vec3(0, 6, 3), color = white)

proc beacons_lit(): bool =
  for id in [
    "build_beacon_windmill", "build_beacon_tower", "build_beacon_maze",
    "build_beacon_lighthouse",
  ]:
    let beacon = Build(find_by_id(id))
    if not ?beacon or beacon.glow < 0.05:
      return false
  true

proc player_aboard(): bool =
  let p = player.position - position
  p.x >= -2.5 and p.x <= 1.5 and p.z >= -4.5 and p.z <= 3.5 and p.y >= -0.5 and
    p.y <= 4.5

say "The boat is asleep. Light the mainland's four beacons to wake it.",
  width = 6.0, height = 1.5

while not beacons_lit():
  sleep 2

hoist_sail()
glow = 0.2
say "All aboard! Step on deck to sail.", width = 6.0, height = 1.5

move me
speed = 6
var at_dock = true

forever:
  if player_aboard():
    say ""
    sleep 1.5
    if at_dock:
      forward 72
      at_dock = false
    else:
      turn 180
      forward 72
      turn 180
      at_dock = true
    # wait for the rider to disembark before arming the next trip
    while player_aboard():
      sleep 0.5
    say "Step aboard to sail back.", width = 5.0, height = 1.5
  else:
    sleep 0.5
