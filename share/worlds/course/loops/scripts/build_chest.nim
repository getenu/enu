# The reward on Chest Island: when Salty arrives, up goes the flag.
lock = true
speed = 0
turn 180 # face arriving visitors
color = brown
box(2, 2, 2, at = vec3(-1, 0, -1), color = brown) # the chest

var raised = false
forever:
  if not raised:
    let salty = find_by_id("bot_salty")
    if not salty.is_nil and salty.position.x > 39.0:
      raised = true
      echo "COURSE: flag raised"
      8.times(i): # flagpole climbs block by block
        box(vec3(2, i, 0), vec3(2, i, 0), color = white)
        sleep 0.1
      box(vec3(3, 5, 0), vec3(5, 7, 0), color = green) # the flag
      say "# You helped Salty! That loop SAVED him.", width = 3.0
  sleep 0.5
