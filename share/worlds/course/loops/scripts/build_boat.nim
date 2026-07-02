# The lost boat. Waits out at sea; when the lamp lights, she sails home
# to the dock. (Same trigger as the lamp, own latch.)
# The unit faces east in its start transform, so `forward` sails home.
lock = true
const TARGET = 10.0

speed = 0
color = brown
box(vec3(-1, 0, -4), vec3(1, 0, 0), color = brown) # hull
box(vec3(-1, 1, -3), vec3(1, 1, -1), color = brown) # deck
color = white
box(vec3(0, 2, -2), vec3(0, 5, -2), color = white) # mast
box(vec3(-1, 3, -2), vec3(-1, 4, -2), color = white) # sail

var sailing = false
forever:
  if not sailing:
    for b in Build.all:
      if b.id == "build_lighthouse":
        let height = b.bounds.max.y - b.bounds.min.y
        if height >= TARGET:
          sailing = true
          echo "COURSE: boat sailing home"
          move me
          speed = 2
          forward 22
  sleep 0.5
