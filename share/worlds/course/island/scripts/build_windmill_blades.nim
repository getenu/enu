speed = 0

# The sails pivot on the hub. This anchor tips the spin axis onto the
# axle, so `turn right` swings the sails like a real windmill.
anchor:
  lean right, 90

# Four sails in a pinwheel around the hub at (0, 0, 0).
for i in 1 .. 6:
  place(0,  i,  0, brown); place(0,  i, -1, white)   # up sail
  place(0, -i,  0, brown); place(0, -i,  1, white)   # down sail
  place(0,  0,  i, brown); place(0,  1,  i, white)   # near sail
  place(0,  0, -i, brown); place(0, -1, -i, white)   # far sail
place(0, 0, 0, black)   # hub

move me

# The blades are stuck! Make them turn.
# hint: things that should happen over and over live inside `forever:`
# hint: try a small `sleep` between turns to set the speed
