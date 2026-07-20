lock = true

# Tall progress board, off to the player's right and just out of the opening
# view. Its always-on message is the live objective checklist; the course
# director (build_course) keeps it up to date by reading world state. Not
# clickable — the checklist is the whole point. The player faces it from the
# west, so the white face is on the -X side.
color = brown

# long post, planted
box(vec3(-1, 0, -1), vec3(1, 20, 1), color = brown)

# tall panel, thin in X, facing the player (-X). Brown frame + white face.
box(vec3(-1, 12, -6), vec3(0, 27, 6), color = brown)     # frame slab
box(vec3(-2, 13, -5), vec3(-1, 26, 5), color = white)    # white face on -X

# hang the checklist sign on the white face, always facing the player
turn left        # face -X, toward the player / spawn side
up 20
forward 2
# The checklist is a multi-line markdown panel (renders far cleaner than a
# multi-line bubble). Keep it open so it shows without a click; the director
# fills in `.more` with live world state.
let board = say("### Objectives", "Loading progress...", width = 7.0,
  height = 6.0, size = 260)
board.open = true
