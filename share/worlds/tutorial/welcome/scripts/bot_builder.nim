lock = true
color = brown
speed = 2

# The cottage builder, standing by his storm-breached wall. He cycles
# through his worries when the player comes close.
var line = 0
let lines = [
  "Storm took half my wall clean off.",
  "If you've got blocks, patch her up -- code works too, I'm not picky.",
  "Weather-tight means no holes big enough to walk through.",
]

-idle:
  turn start_position
  sleep 2

-talk:
  turn player
  say lines[line]
  line = (line + 1) mod lines.len
  sleep 5

loop:
  nil -> idle
  if player.near(10):
    idle -> talk
  talk -> idle
