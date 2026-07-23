lock = true
speed = 0

# The marked spot. Something large is reserved to stand right here — you just
# can't see it yet. The pad stays visible so you always know where "here" is.
color = red
cylinder(size = 14, height = 1, at = vec3(0, 0, 0), color = red)    # landing pad
cylinder(size = 8, height = 1, at = vec3(0, 0, 0), color = white)   # inner ring
place(0, 0, 0, red)                                                 # cover origin

turn 180        # face the approach (player comes from the +Z side)
up 4
let s = say("- Reserved",
  """
  # Reserved

  This spot is reserved for the **invisible rats' rocket**.

  You can't see the rocket. That is, rather, the point. Help the rat-catcher
  make the walls invisible and it may — occasionally — turn up.
  """,
  width = 3.0, height = 2.0)
s.billboard = true

forever:
  sleep 1
