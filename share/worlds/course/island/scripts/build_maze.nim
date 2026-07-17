lock = true
speed = 0

## Maze: a solid brown block (x -1..23, z -1..23, height 2) carved into a
## single connected path — entrance -> T1 -> connector -> T2 -> exit — with
## two dead-end pockets (green-capped) at the T-junctions' wrong turns.
## Outer boundary is closed except the entrance (west) and exit (east) gaps;
## every corridor has solid wall on both sides. Corridor width 3, walls 1
## thick / 2 high.
##
##   Lane 1 (entrance + wrong-turn spur): x -1..17, z 19..21
##   T1 junction (turn north = correct):  x 11..13, z 19..21
##   Connector (north-south):             x 11..13, z  6..19
##   T2 junction (turn east = correct):   x 11..13, z  4..6
##   Dead-end spur (wrong turn, north):   x 11..13, z  1..3
##   Lane 2 / exit corridor:              x 11..23, z  4..6
## Entrance pad (white): x -3..-1, z 19..21
## Exit pad (green):     x 23..25, z  4..6

box(at = vec3(-1, 0, -1), to = vec3(23, 1, 23), color = brown)

# Entrance corridor + T1 junction + dead-end-east spur (open west = entrance)
box(at = vec3(-1, 0, 19), to = vec3(17, 1, 21), color = eraser)
# Connector: T1 -> T2 (turning north is the correct choice at T1)
box(at = vec3(11, 0, 6), to = vec3(13, 1, 19), color = eraser)
# Dead-end-north spur (the wrong choice at T2: keep going straight)
box(at = vec3(11, 0, 1), to = vec3(13, 1, 3), color = eraser)
# T2 junction + exit corridor (open east = exit)
box(at = vec3(11, 0, 4), to = vec3(23, 1, 6), color = eraser)

# Clearance pocket for build_beacon_maze (world -52,-14 / local x 7..9, z 3..5)
# — an isolated void inside the solid fill, not connected to any corridor.
box(at = vec3(6, 0, 2), to = vec3(9, 1, 6), color = eraser)

# Green dead-end caps
box(at = vec3(18, 0, 19), to = vec3(18, 1, 21), color = green)
box(at = vec3(11, 0, 0), to = vec3(13, 1, 0), color = green)

# Entrance pad (white) and exit pad (green)
box(at = vec3(-3, 0, 19), to = vec3(-1, 0, 21), color = white)
box(at = vec3(23, 0, 4), to = vec3(25, 0, 6), color = green)

# --- Scrolling signs (tutorial-1's scroller pattern) ---
proc make_sign(): Sign =
  say("` `", width = 6.0, height = 2.5, size = 1400)

proc scroller(sign: Sign, msg: string, pause = 0, len = msg.len): proc() =
  var current = msg
  var counter = 0

  result = proc() =
    if current == msg and counter < pause:
      inc counter
    else:
      counter = 0
      current = current[1 ..^ 1] & current[0]
      sign.message = "`" & current[0 .. (len - 1)].strip(leading = false) & "`"

drawing = false

back 20
up 4
left 1
turn left
let entrance_sign = make_sign()
turn right

right 24
forward 15
turn left
let exit_sign = make_sign()

let entrance_scroller = entrance_sign.scroller(" START HERE! ", 0, 7)
let exit_scroller = exit_sign.scroller(" FINISH! ", 0, 7)

forever:
  entrance_scroller()
  exit_scroller()
  sleep 0.2
