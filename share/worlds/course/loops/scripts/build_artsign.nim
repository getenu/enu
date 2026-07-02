# Art Beach: no obstacle, no gate — just "make something cool."
lock = true
speed = 0
color = white
box(vec3(0, 0, 0), vec3(0, 3, 0), color = white) # signpost
turn right # face the road, to the east

let art_sign = say("- Art Beach",
  """
  # Art Beach

  Not everything needs a *reason*. Loops make great art.

  Open the green pad and try something like:

  ```nim
  color = cycle(green, white, blue)
  20.times:
    forward 2
    turn 25
    up 1
  ```

  Change the numbers. Change the colors. See what happens —
  that's the whole assignment.
  """,
  width = 3.5)

var praised = false
forever:
  if not praised:
    for b in Build.all:
      if b.id == "build_myart":
        let size = b.bounds.max - b.bounds.min
        if size.x * size.y * size.z >= 60.0 or size.y >= 8.0:
          praised = true
          echo "COURSE: art praised"
          art_sign.message = "# A masterpiece!"
  sleep 1
