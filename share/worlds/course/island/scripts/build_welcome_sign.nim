lock = true
scale = 0.1

let page =
  """
  # Welcome to Enu

  You're standing in an ordinary Enu level. This sign, the windmill, the bots,
  the whole island — all of it is built from the same blocks and scripts you
  have. There's no special engine magic here: it's a world anyone could make,
  and remake.

  So poke at it. Break it. Fix it. Open a unit's code and change it.

  ---

  - [Reset this level](<nim://reset_level()>)
  - [Turn on all the tools](<nim://player.tools = {CodeMode, BlueBlock, RedBlock, GreenBlock, BlackBlock, WhiteBlock, BrownBlock, PlaceBot}; player.can_fly = true>)
  """

# --- notice board: one centre post + framed panel ---
# Ground sits at ~local y20 here (origin y3, scale 0.1), so the panel rides
# high up the post and the post sinks below y20 to look planted.
color = brown

# single stout post, long and sunk into the ground so it reads as planted
box(width = 4, height = 44, depth = 4, at = vec3(-2, 0, -2), color = brown)

# panel: brown frame with a white face, held up near the top of the post
box(width = 22, height = 10, depth = 1, at = vec3(-11, 34, 0), color = brown)
box(width = 18, height = 6, depth = 1, at = vec3(-9, 36, 0), color = white)

# overhanging cap
box(width = 24, height = 1, depth = 2, at = vec3(-12, 44, 0), color = brown)

# --- scrolling billboard across the white face ---
proc scroller(sign: Sign, msg: string, len: int): proc() =
  var current = msg
  result = proc() =
    current = current[1 ..^ 1] & current[0]
    sign.message = "`" & current[0 ..< len] & "`"

# park the turtle just in front of the white face, centred
turn 180        # face +Z, toward the player / spawn side
up 37           # the sign auto-shifts up by (height - 1); centre it on the face
right 9
forward 1       # step onto the player-facing side of the panel
let s = say("` `", page, width = 18.0, height = 3.0, size = 5200)

let scroll = s.scroller("   WELCOME.......... CLICK PLEASE..........   ", 13)

forever:
  scroll()
  sleep 0.22
