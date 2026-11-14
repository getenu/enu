import testing

# Checks a level saved by Enu 0.2.2. Every other unit's files are as 0.2.2
# wrote them, and this unit's data is too. `nim test_world` runs the level
# twice on one copy: the first run converts it, the second loads what the
# first saved, so these checks must hold both times.
#
# The maze (build_f4qf20mu45gj8) renames itself to build_maze on the first run.
# Its holes cut into the blocks its script draws; a rename used to drop them.
# Positions are world coordinates sampled from the maze's 0.2.2 edits and from
# what its script draws.

speed = 0

proc build_named(id: string): Build =
  for build in all_builds():
    if build.id == id:
      return build

proc has_thing(id: string): bool =
  for thing in all_things():
    if thing.id == id:
      return true

proc at(coords: openarray[int], i: int): Vector3 =
  vec3(coords[i].float, coords[i + 1].float, coords[i + 2].float)

const computed = [
  -18,1,138, -18,2,139, -18,3,141, -18,5,139, -17,2,138, -17,4,140,
  -17,6,141, -17,8,140, -16,3,139, -16,7,141, -16,9,135, -15,5,139
]

const holes = [
  71,3,-9, 90,6,54, 93,4,49, 105,2,7, -17,5,131, -28,8,122,
  105,7,29, -25,6,139, -12,3,4, -31,1,129, -23,1,137, -27,8,139,
  102,3,3, -24,1,126, 107,1,28, -19,1,132, 89,5,54, 104,2,5,
  -51,0,103, 98,3,11, 107,3,8, -22,9,140, -16,6,138, 69,5,-7,
  99,3,2, 111,9,31, -32,1,126, 95,7,15, -17,4,134, -12,3,3,
  88,1,53, 108,3,29, -13,5,5, 111,5,29, -32,7,130, -31,8,121,
  103,3,5, -28,2,124, -27,1,125, 98,6,10
]

const manual = [
  -32,5,106, -24,0,108, -22,1,105, -23,0,106, -22,4,108, -32,5,105,
  -22,0,107, -32,2,107, -26,0,107, -22,4,110, -22,2,102, -28,0,106
]

const manual_colors = [black, black, black, black, black, black, black, black, black, black, black, black]

proc all_drawn(): bool =
  var i = 0
  while i < computed.len:
    if not has_block_at(computed.at(i)):
      return false
    i += 3
  true

# Nothing tells a script when another one finishes, so wait for the maze to
# draw what it should and then stop changing.
var waited = 0.0
var steady = 0.0
var last_bounds: WorldBox
while waited < 120 and steady < 3:
  sleep 0.5
  waited += 0.5
  let maze = build_named("build_maze")
  if maze.is_nil or not all_drawn() or maze.pending_block_updates > 0 or
      maze.bounds != last_bounds:
    steady = 0
    if not maze.is_nil:
      last_bounds = maze.bounds
  else:
    steady += 0.5

suite "A level saved by 0.2.2":
  test "the maze renames itself":
    check has_thing("build_maze")
    check not has_thing("build_f4qf20mu45gj8")

  test "a bot loads":
    check has_thing("bot_aqslupunw4ndq")

  test "the maze draws":
    check all_drawn()

  test "the maze keeps its holes":
    var i = 0
    while i < holes.len:
      check not has_block_at(holes.at(i))
      i += 3

  test "the maze keeps its manual blocks":
    var i = 0
    while i < manual.len:
      check block_color_at(manual.at(i)) == manual_colors[i div 3]
      i += 3

  test "scripts can use the renamed maze":
    check maze.id == "build_maze"

test_summary()
