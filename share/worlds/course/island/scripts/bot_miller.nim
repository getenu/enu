lock = true
color = white
speed = 2

# The miller frets about his stuck windmill, cycling through his worries.
var line = 0
let grumbles = [
  "My windmill! The blades are stuck fast...",
  "If only someone who knew code could open those blades up.",
  "It just needs to turn, forever really.",
]

-wander:
  forward 2 .. 4
  turn -60.0 .. 60.0
  sleep 1 .. 2

-come_home:
  turn start_position
  forward 3

-fret:
  turn player
  say grumbles[line]
  line = (line + 1) mod grumbles.len
  sleep 5

loop:
  nil -> wander
  if start_position.far(6):
    wander -> come_home
  if start_position.near(2):
    come_home -> wander
  if player.near(9):
    (wander, come_home) ==> fret
  fret -> wander
