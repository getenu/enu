# Interactive "play" beat — drive a loop before writing one. Tap a count
# and a loop stacks that many blocks, so the player feels "N = how many
# times" with no typing. (grow clears + redraws; called from the sign's
# nim:// links — needs an interactive click to test.)
color = white
box(width = 1, height = 4, depth = 1, color = white) # signpost

proc grow(n: int) =
  for i in 0 ..< 25:
    place(2, i, 0, eraser) # clear the column beside the post
  for i in 0 ..< n:
    place(2, i, 0, red)

let try_sign = say("- You drive the loop",
  """
  # You drive the loop

  Tap a number — a loop stacks that many blocks:

  - [Stack 5](<nim://grow(5)>)
  - [Stack 10](<nim://grow(10)>)
  - [Stack 20](<nim://grow(20)>)

  Same loop, different count. That's all a loop does: **repeat, N times.**
  """,
  width = 4.0)
