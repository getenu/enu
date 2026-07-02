# The target ring for the water-tower exercise: the tank should line up
# here. (Floats at world y = 12: mesa top 4 + legs 6 + 2.)
lock = true
speed = 0
color = white

box(vec3(-1, 0, 1), vec3(5, 0, 1), color = white)
box(vec3(-1, 0, -5), vec3(5, 0, -5), color = white)
box(vec3(-1, 0, 0), vec3(-1, 0, -4), color = white)
box(vec3(5, 0, 0), vec3(5, 0, -4), color = white)

var done = false
forever:
  if not done:
    for b in Build.all:
      if b.id == "build_watertower":
        if b.bounds.max.y >= 11.0:
          done = true
          echo "COURSE: water tower reaches the ring"
  sleep 0.5
