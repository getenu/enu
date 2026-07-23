lock = true
speed = 0

# ---- The Summit Gate: end-cap of the island course ----
# Two white pillars with green caps frame a dark portal to whatever comes
# next. It teases the next level -- it doesn't open one. Portal faces west,
# into the sunset; the plaza and beacon are on the approach (east) side.

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

# --- pillars (2x2, 12 tall) with green caps ---
box(vec3(-1, 0, -7), vec3(0, 11, -6), color = white)   # north pillar
box(vec3(-1, 0,  6), vec3(0, 11,  7), color = white)   # south pillar
box(vec3(-1, 12, -7), vec3(0, 13, -6), color = green)  # north cap
box(vec3(-1, 12,  6), vec3(0, 13,  7), color = green)  # south cap

# --- lintel across the top, with a green crown ---
box(vec3(-1, 11, -6), vec3(0, 12, 6), color = white)
box(vec3(-1, 13, -6), vec3(0, 13, 6), color = green)

# --- inset dark portal plane between the pillars ---
box(vec3(0, 0, -5), vec3(0, 11, 5), color = black)

# --- plinths under the pillars + stone plaza on the approach side ---
box(vec3(-2, 0, -8), vec3(1, 0, -5), color = white)
box(vec3(-2, 0,  5), vec3(1, 0,  8), color = white)
box(vec3(1, 0, -5), vec3(7, 0, 4), color = white)      # plaza floor

# --- skirt: two courses below the base, dropping past the lowest terrain under
# the footprint so the base plants into the slope instead of floating a lip ---
box(vec3(-2, -2, -8), vec3(1, -1, -5), color = white)
box(vec3(-2, -2,  5), vec3(1, -1,  8), color = white)
box(vec3(1, -2, -5), vec3(7, -1, 4), color = white)

# --- scrolling teaser sign, floating above the portal ---
drawing = false
up 15
right 4
let teaser = say("` `", width = 11.0, height = 2.0, size = 1.25)
let scroll = teaser.scroller(" NEXT LEVEL... SOON ", 0, 12)

forever:
  scroll()
  sleep 0.2
