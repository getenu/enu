lock = true
speed = 0

# The invisible rats' rocket. It's parked on the pad the whole time — you just
# can't see it. Once you've made the walls invisible so the rats can reach it,
# it turns up a little later... and then blinks in and out for the rest of the
# game. Proof, if you needed it, that the invisible rats were real all along.

# --- draw the rocket, then hide the whole thing ---
color = white
cylinder(size = 8, height = 14, at = vec3(0, 0, 0), color = white)   # body
cylinder(size = 6, height = 2, at = vec3(0, 14, 0), color = red)     # shoulder
cylinder(size = 4, height = 2, at = vec3(0, 16, 0), color = red)     # nose
cylinder(size = 2, height = 2, at = vec3(0, 18, 0), color = red)     # tip

# portholes down the front face (body radius ~4, so z = 4 is the surface)
place(0, 10, 4, blue)
place(0, 7, 4, blue)
place(0, 4, 4, blue)

# four fins
box(vec3(4, 0, 0), vec3(6, 4, 0), color = red)
box(vec3(-6, 0, 0), vec3(-4, 4, 0), color = red)
box(vec3(0, 0, 4), vec3(0, 4, 6), color = red)
box(vec3(0, 0, -6), vec3(0, 4, -4), color = red)

place(0, 0, 0, black)   # cover the origin block

show = false   # unseen until the rats can reach it

# The exercise is done when the foundation's walls have been made invisible.
# The foundation flags that by setting its (undrawn) pen colour to red.
proc walls_invisible(): bool =
  let b = Build(find_by_id("build_rat_foundation"))
  ?b and b.color == red

while not walls_invisible():
  sleep 2
sleep 90          # let the moment breathe, then arrive
show = true
forever:
  sleep 150       # a few minutes on, a few minutes off, forever
  show = not show
