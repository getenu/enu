# The lamp room, floating at the target height. It starts DARK because the
# tower below is unfinished. This unit is also the level's checker + reward:
# it watches build_lighthouse and lights up once the tower reaches it.
#
# (Goal -> reaction template: poll a condition in `forever:`, latch, react.)

const target = 10
var lit = false

color = black
box(width = 3, height = 3, depth = 3, color = black) # dark lamp = the target

forever:
  if not lit:
    for b in Build.all:
      if b.id == "build_lighthouse":
        let tower_height = b.bounds.max.y - b.bounds.min.y
        if tower_height >= target.float:
          lit = true
          echo "Lighthouse reached ", target, " — lighting the lamp!"
          box(width = 3, height = 3, depth = 3, color = white) # lamp on
          for d in 1 .. 24: # beam out over the sea (north = -z)
            place(0, 1, -1 - d, white)
  sleep 0.5
