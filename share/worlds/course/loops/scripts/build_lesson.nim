# The "tell" beat: name the concept, short and grounded.
lock = true
speed = 0
color = white
box(vec3(0, 0, 0), vec3(0, 3, 0), color = white) # signpost
turn 180 # face the road

say "- What's a loop?",
  """
  # What's a **loop**?

  You already know loops!

  - "Do 10 jumping jacks."
  - "Stir the pot 20 times."

  A loop tells the computer: **do this again and again**, a set number
  of times. In code it looks like this:

  ```nim
  10.times:
    forward 1
    up 1
  ```

  That's 10 steps of a staircase — from 3 lines of code. The spiral on
  the beach? A loop. The dashes on the road? A loop.

  Try one yourself at the next sign. →
  """,
  width = 4.0
