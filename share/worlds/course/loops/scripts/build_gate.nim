# The harbor gate: blocks the causeway to the pier until the lighthouse
# is finished. Same trigger as the lamp, its own latch.
lock = true
speed = 0
const TARGET = 10.0

color = black
box(vec3(-3, 0, 0), vec3(3, 4, 0), color = black)
box(vec3(-3, 4, 0), vec3(3, 4, 0), color = white) # top rail

turn 180 # face the approaching player
let gate_sign = say("- The pier is closed",
  """
  # Pier closed!

  No boats can dock while the lighthouse is dark.

  Finish the tower and the gate will open.
  """,
  width = 2.5)

var open = false
forever:
  if not open:
    for b in Build.all:
      if b.id == "build_lighthouse":
        let height = b.bounds.max.y - b.bounds.min.y
        if height >= TARGET:
          open = true
          echo "COURSE: gate open"
          gate_sign.message = "- Welcome to the pier!"
          box(vec3(-2, 0, 0), vec3(2, 3, 0), color = eraser) # doorway
  sleep 0.5
