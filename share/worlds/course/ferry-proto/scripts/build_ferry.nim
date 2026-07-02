# The ferry is broken! The robots are stranded on the deck.
# Drive it back and forth, forever:
#
#   move me
#   speed = 3
#   forever:
#     forward 25
#     sleep 3
#     back 25
#     sleep 3

# (The ferry faces east, so local coords are rotated: +local-x is south,
# +local-z is west. The anchors below center the deck under the crew.)
color = black
box(6, 1, 6, at = vec3(-3, 0, -6))
box(6, 1, 1, at = vec3(-3, 1, -1), color = white) # back rail
