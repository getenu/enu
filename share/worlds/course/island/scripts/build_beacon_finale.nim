lock = true
speed = 0

# Finale progress beacon: brown post, white lantern -- same pattern as the
# mainland beacons. The course director kicks our glow when E6 + E7 are
# done; the lantern turns green and we take over pulsing. That moment is
# also when flight unlocks, so we carry the "sky is yours" sign.
box(vec3(-1, 0, -1), vec3(0, 3, 0), color = brown)
box(vec3(-1, 4, -1), vec3(0, 5, 0), color = white)

say "Beacons all lit. The sky is yours -- double-jump to fly.",
  width = 6.0, height = 1.0, size = 900

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
