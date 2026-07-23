lock = true

# Progress board, off to the player's right and just out of the opening view.
# Its always-on message is the live objective checklist; the course director
# (build_course) keeps it up to date by reading world state. Click it to open the
# fuller progress panel (also director-driven). The player faces it from the
# west, so the board face is on the -X side.
color = brown

# post, planted — shorter than the original (the board used to ride too high),
# but long enough to read as a real post below the board.
box(vec3(-1, 0, -1), vec3(1, 12, 1), color = brown)

# tall, fairly narrow panel, thin in X, facing the player (-X). Brown frame all
# around, with the single face layer directly behind the checklist painted black
# so the dark message panel reads cleanly against it.
box(vec3(-1, 6, -5), vec3(0, 21, 5), color = brown)     # backing slab / frame
box(vec3(-2, 7, -4), vec3(-1, 20, 4), color = black)    # black face on -X

# hang the checklist sign on the board face, always facing the player
turn left        # face -X, toward the player / spawn side
up 7
forward 2
right 4          # shift the anchor so the panel centres on the face
# The checklist is a multi-line markdown panel. It lives in the sign's in-world
# message (param 1) so it reads on the board itself; the fuller progress writeup
# lives in `more` (param 2) and opens when the board is clicked. The director
# keeps both in sync with world state — this is just the placeholder. Sized so
# all seven objectives fill the title-less face.
say("_Loading progress..._", "_Loading progress..._", width = 9.0,
  height = 14.0, size = 0.52)
