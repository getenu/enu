lock = true
speed = 0

# Progress beacon: a tall brown post topped by a lantern. The course director
# kicks our glow when this site's exercise is done — the lantern turns green,
# lights a flame, and we take over pulsing so it reads from across the map.
box(vec3(-1, 0, -1), vec3(0, 9, 0), color = brown)      # 2x2 post, 10 tall
box(vec3(-2, 10, -2), vec3(1, 12, 1), color = white)    # 4x4 lantern cage

forever:
  if glow > 0.05:
    box(vec3(-2, 10, -2), vec3(1, 12, 1), color = green)  # lantern lights
    box(vec3(-1, 13, -1), vec3(0, 15, 0), color = green)  # flame
    place(-1, 16, -1, green)
    place(0, 16, -1, green)
    place(-1, 16, 0, green)
    place(0, 16, 0, green)
    place(0, 17, 0, green)                                # tip
    break
  sleep 0.5

forever:
  glow = 1.0
  sleep 0.6
  glow = 0.3
  sleep 0.6
