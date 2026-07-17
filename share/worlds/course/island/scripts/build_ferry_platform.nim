# ----- the raft: a 5x5 brown plank deck with a low rim -----
box(vec3(-2, 0, -2), vec3(2, 0, 2), color = brown)   # deck
box(vec3(-2, 1, -2), vec3(2, 1, -2), color = brown)  # rim
box(vec3(-2, 1, 2), vec3(2, 1, 2), color = brown)
box(vec3(-2, 1, -1), vec3(-2, 1, 1), color = brown)
box(vec3(2, 1, -1), vec3(2, 1, 1), color = brown)

speed = 5
move me

# The castaways need a ride to the camp across the water!
# hint: `forward 76` glides me all the way to the far pad
# hint: wrap the trip in `forever:` with a `sleep` at each end
# hint: `turn 180` faces me home again
