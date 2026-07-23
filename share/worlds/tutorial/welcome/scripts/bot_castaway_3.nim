lock = true
color = blue
speed = 3

# A castaway marooned on the little island. Wanders the interior, frets at
# the player, and once the ferry raft is running will walk to the landing
# pad, ride the raft across to the peninsula, and settle at the camp.

# Landmarks. The y matches the raft's origin so distance checks read as
# flat xz distance to the raft.
let isle_pad = vec3(176.0, 2.5, -184.0)   # island landing pad centre
let pen_pad = vec3(124.0, 2.5, -128.0)    # peninsula landing pad centre

# This castaway's own cell on the 5x5 raft deck, and where they settle in
# camp -- both distinct per bot so they never stack up.
let deck_off = vec3(0.0, 1.2, 1.5)
let settle_at = vec3(117.0, 3.0, -125.0)

var has_ridden = false
var ferry_seen_away = false
var line = 0
let lines = [
  "Castaway is the word. No boat, no bridge, nothing at all.",
  "A warm camp and soup wait across the water. Me? I sink like a stone.",
]

proc ferry(): Thing =
  find_by_id("build_ferry_platform")

-wander:
  forward 2 .. 4
  turn -50.0 .. 50.0
  sleep 1 .. 2

-come_home:
  turn start_position
  forward 3

-greet:
  turn player
  say lines[line]
  line = (line + 1) mod lines.len
  sleep 5

-to_pad:
  turn isle_pad
  if me.position.distance_to(isle_pad) > 3.0:
    forward 2
  else:
    sleep 0.4

-ride:
  let f = ferry()
  while ?f and f.position.distance_to(pen_pad) > 6.0:
    me.position = f.position + deck_off
    sleep 0.3

-disembark:
  turn settle_at
  forward 3

-settle:
  if me.position.distance_to(settle_at) > 3.0:
    turn settle_at
    forward 2
  else:
    turn -80.0 .. 80.0
    forward 1
    sleep 1 .. 2

loop:
  let f = ferry()
  if ?f and f.position.distance_to(isle_pad) > 8.0:
    ferry_seen_away = true

  nil -> wander

  # tether the interior wandering near home
  if not has_ridden and start_position.far(9):
    wander -> come_home
  if not has_ridden and start_position.near(3):
    come_home -> wander

  # fret at the player while still marooned
  if not has_ridden and player.near(8):
    (wander, come_home) ==> greet
  greet -> wander

  # once the raft is running and waiting at the island, go board it
  if ferry_seen_away and not has_ridden and ?f and
      f.position.distance_to(isle_pad) < 5.0:
    (wander, come_home, greet) -> to_pad

  # lock onto the deck when both the bot and the raft are at the pad
  if ?f and f.position.distance_to(isle_pad) < 3.5 and
      me.position.distance_to(f.position) < 4.5:
    to_pad ==> ride do:
      has_ridden = true

  # the ride ends when the raft reaches the peninsula
  ride -> disembark

  # walk into camp, then stay put
  if me.position.distance_to(settle_at) < 3.5:
    disembark -> settle
