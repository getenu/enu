lock = true
speed = 0

# Wooden dock jutting north from the headland out over the strait. Origin
# sits at the shore (199, 2, -88); the deck rides at world y3 on pilings
# that drop into the water, ending in a wide T-head where the boat berths.
# Local y: deck planks at +1 (world 3), pilings 0..-2 (world 2..0),
# railing stubs at +2 (world 4).

const DECK_Y = 1

# --- Approach deck: 4 wide (local x -2..1), running north 10 m ---
box(vec3(-2, DECK_Y, 0), vec3(1, DECK_Y, -10), color = brown)

# --- T-head landing: 8 wide (local x -4..3), 5 deep at the far end ---
box(vec3(-4, DECK_Y, -10), vec3(3, DECK_Y, -14), color = brown)

# --- Pilings: drop from just under the deck into the water ---
var posts: seq[array[2, int]]
for z in countup(0, 10):
  if z mod 3 == 0:
    posts.add [-2, -z]
    posts.add [1, -z]
for x in [-4, -1, 0, 3]:
  posts.add [x, -10]
  posts.add [x, -14]
posts.add [-4, -12]
posts.add [3, -12]
for p in posts:
  box(vec3(p[0], DECK_Y - 1, p[1]), vec3(p[0], DECK_Y - 3, p[1]), color = brown)

# --- Railing stubs: short brown posts along the approach edges ---
for z in countup(0, 9):
  if z mod 3 == 0:
    place(-2, DECK_Y + 1, -z, brown)
    place(1, DECK_Y + 1, -z, brown)
# corner posts on the T-head (leaving the north edge open for berthing)
for z in [-10, -12, -14]:
  place(-4, DECK_Y + 1, z, brown)
  place(3, DECK_Y + 1, z, brown)

# --- Shore apron: brown fill so the deck meets the land cleanly ---
box(vec3(-2, 0, 0), vec3(1, 0, 1), color = brown)
