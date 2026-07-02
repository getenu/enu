# The far rim marker + the bridge checker: when the bridge reaches the
# east mesa, the town celebrates.
lock = true
speed = 0
color = white
box(vec3(0, 0, 2), vec3(0, 0, -2), color = white) # landing stripe

var done = false
forever:
  if not done:
    for b in Build.all:
      if b.id == "build_bridge":
        let span = b.bounds.max.x - b.bounds.min.x
        if span >= 13.0:
          done = true
          echo "COURSE: bridge spans the gorge"
          say "# The stage can roll again! Thanks, partner.", width = 4.0
  sleep 0.5
