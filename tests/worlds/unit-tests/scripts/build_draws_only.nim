# Only draws: enough blocks that drawing parks it, but no sleep or movement.
# build_asap_check checks it's shown once it finishes.
speed = 0
for x in 0 ..< 20:
  for z in 0 ..< 20:
    place x, 0, z
