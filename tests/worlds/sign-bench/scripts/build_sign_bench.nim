## Worst-case signs, for comparing sign renderers (`nim build` against
## `nim build -d:no_pages`). Sixteen marquees change every tick, next to
## sixteen signs that never change. Run with ENU_PERF_LOG=1 and compare the
## PERF lines' fps.

lock = true
drawing = false
speed = 0

const
  ROWS = 4
  COLS = 4
  TEXT = "  SIGN BENCH...WORST CASE...EVERY FRAME...  "
  STILL = """
### A sign that never changes

Some **bold**, some *italic*, a list:

- one
- two
"""

proc marquee(offset: int): string =
  let i = offset mod TEXT.len
  "`" & (TEXT[i ..^ 1] & TEXT[0 ..< i])[0 ..< 16] & "`"

turn 180 # face the player
up 2
left 29
var marquees: seq[Sign]
for row in 0 ..< ROWS:
  for col in 0 ..< COLS:
    marquees.add say(marquee(row * COLS + col), width = 6.0, height = 1.5,
        size = 0.8)
    right 7
  left 7 * COLS
  up 2.5

# The still signs, off to the right.
right 7 * COLS + 2
down 2.5 * ROWS
for row in 0 ..< ROWS:
  for col in 0 ..< COLS:
    discard say(STILL, width = 6.0, height = 4.0, size = 0.4)
    right 7
  left 7 * COLS
  up 4.5

var tick = 0
forever:
  inc tick
  for i, sign in marquees:
    sign.message = marquee(tick + i)
  sleep 0
