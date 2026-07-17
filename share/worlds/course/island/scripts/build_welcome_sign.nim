lock = true
scale = 0.1

let page =
  """
  # Welcome to Enu

  Enu is a world you reprogram from the inside — everything you see is
  running on code you can open and change. Poke at it. Break it. Fix it.

  ## Your objective

  Wake the sleeping boat by fixing up the mainland:

  - Get the **windmill** blades turning
  - Raise the **lookout tower**
  - Guide the **maze bot** to its exit
  - Light the **dark lighthouse**

  Then sail out and help the **castaways** stranded on the isle beyond.

  A progress **beacon** lights up green each time you finish a task.

  ---

  [Reset this level](<nim://reset_level()>)
  """

# --- notice board: two posts + framed panel ---
color = brown

# base sill (also covers the default block at local 0,0,0)
box(width = 20, height = 1, depth = 2, at = vec3(-10, 0, 0), color = brown)

# posts to the ground
box(width = 2, height = 13, depth = 2, at = vec3(-10, 0, 0), color = brown)
box(width = 2, height = 13, depth = 2, at = vec3(8, 0, 0), color = brown)

# panel: brown frame with a white face
box(width = 22, height = 10, depth = 1, at = vec3(-11, 11, 0), color = brown)
box(width = 18, height = 6, depth = 1, at = vec3(-9, 13, 0), color = white)

# overhanging cap
box(width = 24, height = 1, depth = 2, at = vec3(-12, 21, 0), color = brown)

# --- scrolling billboard on the panel face ---
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

# park the turtle just in front of the white face, centred
turn 180        # face +Z, toward the player / spawn side
up 14           # sign auto-shifts up by (height - 1); land it on the face
right 9
forward 1       # step onto the player-facing side of the panel
let s = say("` `", page, width = 18.0, height = 3.0, size = 2600)

let scroll = s.scroller(" CLICK ME! ", 0, 9)

forever:
  scroll()
  sleep 0.2
