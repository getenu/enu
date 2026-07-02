# Counts robots that made it across. (Origin on the east cliff.)
lock = true
speed = 0
color = white

var done = false
forever:
  if not done:
    var count = 0
    for b in Bot.all:
      if b.position.x > 32.0:
        count = count + 1
    if count >= 4:
      done = true
      echo "COURSE: the pack made it across"
      say "# The pack made it! Ferry service restored.", width = 4.0
  sleep 1
