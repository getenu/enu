# Stepped pyramid (40 m base). Built at full scale: 1 m blocks carry a
# pyramid fine — scale things to fit a space or a scene's vibe, not for
# detail. (Contrast with furniture, which needs scale = 0.25 to read.)
let base = 40
let tiers = 20

for tier in 0 ..< tiers:
  let offset = tier
  let size = base - offset * 2
  if size <= 0:
    break
  box(
    width = size,
    height = 1,
    depth = size,
    at = vec3(offset.float, tier.float, -(offset + size).float),
    color = brown,
  )

box(vec3(19, tiers, -22), vec3(20, tiers + 1, -21), white) # capstone
