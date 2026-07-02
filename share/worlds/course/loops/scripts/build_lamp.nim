# The lamp room, floating at the target height. Dark until the tower
# below reaches it — this unit is also the checker and the reward.
lock = true
speed = 0
const TARGET = 10.0

color = black
box(3, 3, 3, at = vec3(0, 0, -2), color = black)

var lit = false
forever:
  if not lit:
    for b in Build.all:
      if b.id == "build_lighthouse":
        let height = b.bounds.max.y - b.bounds.min.y
        if height >= TARGET:
          lit = true
          echo "COURSE: lighthouse complete - lamp lit"
          box(3, 3, 3, at = vec3(0, 0, -2), color = white)
          26.times(i): # the beam grows out over the sea
            box(vec3(1, 1, -3 - i), vec3(1, 1, -3 - i), color = white)
            sleep 0.05
  sleep 0.5
