lock = true
speed = 0

# Progress beacon: brown post, white lantern. The course director kicks our
# glow when this site's exercise is done — the lantern turns green, grows a
# crown, and we take over pulsing.
box(vec3(-1, 0, -1), vec3(0, 3, 0), color = brown)
box(vec3(-1, 4, -1), vec3(0, 5, 0), color = white)

forever:
  if glow > 0.05:
    box(vec3(-1, 4, -1), vec3(0, 5, 0), color = green)
    place(-2, 5, -1, green)
    place(-2, 5, 0, green)
    place(1, 5, -1, green)
    place(1, 5, 0, green)
    place(-1, 6, -1, green)
    place(-1, 6, 0, green)
    place(0, 6, -1, green)
    place(0, 6, 0, green)
    break
  sleep 0.5

forever:
  glow = 0.55
  sleep 0.7
  glow = 0.15
  sleep 0.7
