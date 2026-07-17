show = false
lock = true

# The course starts on the rise east of the waterfall. A fresh spawn lands
# at the world origin; carry them to the start, grounded. Reloads leave
# anyone who has already moved on alone.
if (player.position - vec3(0, 0, 0)).length < 5:
  player.position = vec3(-219.5, 6, -30.5)
  player.rotation = -7.5
  player.can_fly = false
