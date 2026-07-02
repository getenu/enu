# The "play" beat: drive a loop before writing one. Tap a count, a loop
# stacks that many blocks — you feel what N means without typing.
lock = true
speed = 0
color = white
box(vec3(0, 0, 0), vec3(0, 3, 0), color = white) # signpost
turn 180 # face the road

proc grow(n: int) =
  25.times(i):
    place(-2, i, 0, eraser)
  n.times(i):
    place(-2, i, 0, red)

say "- You drive the loop",
  """
  # You drive the loop

  Tap a number — a loop stacks that many blocks beside this sign:

  - [Stack 5](<nim://grow(5)>)
  - [Stack 10](<nim://grow(10)>)
  - [Stack 20](<nim://grow(20)>)
  - [Clear](<nim://grow(0)>)

  Same loop every time — only the **count** changes.

  Ready? The lighthouse at the end of the road needs you.
  """,
  width = 4.0
