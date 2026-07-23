lock = true
color = red
speed = 4

# Small red crab scuttling on the beach: quick, short side-to-side
# darts, an occasional pause, and a rare "click clack". Tethered close
# to its home spot so it doesn't wander onto the maze plot or the surf.

-scuttle:
  forward 1 .. 3
  turn -90.0 .. 90.0

-pause:
  sleep 0.5 .. 1.5

-come_home:
  turn start_position
  forward 2

-click:
  say "click clack"
  sleep 1.5

loop:
  nil -> scuttle
  if start_position.far(8):
    scuttle -> come_home
  if start_position.near(2):
    come_home -> scuttle
  if 1 in 5:
    scuttle -> pause
  pause -> scuttle
  if 1 in 15:
    scuttle -> click
  click -> scuttle
