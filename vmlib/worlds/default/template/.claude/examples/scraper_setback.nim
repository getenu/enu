# Art-deco setback tower (270 m): hollow tiers stepping inward, a white
# trim course capping each (doubling as its roof slab), a full punched
# window grid on every face, a crown and a needle. Helper procs keep the
# repetition out of the body.
proc tier(inset, y0, y1: int) =
  box(
    vec3(inset, y0, -inset),
    vec3(35 - inset, y1, -(35 - inset)),
    brown,
    fill = false,
  )
  box(vec3(inset, y1, -inset), vec3(35 - inset, y1, -(35 - inset)), white)

proc windows(inset, y0, y1: int) =
  ## 1 x 2 windows in a 4 x 5 grid rhythm, all four faces.
  let lo = inset
  let hi = 35 - inset
  var y = y0 + 2
  while y + 3 < y1:
    var x = lo + 3
    while x < hi - 2:
      box(vec3(x, y, -lo), vec3(x + 1, y + 2, -lo), eraser)
      box(vec3(x, y, -hi), vec3(x + 1, y + 2, -hi), eraser)
      x += 4
    var z = lo + 3
    while z < hi - 2:
      box(vec3(lo, y, -z), vec3(lo, y + 2, -(z + 1)), eraser)
      box(vec3(hi, y, -z), vec3(hi, y + 2, -(z + 1)), eraser)
      z += 4
    y += 5

tier(0, 0, 79)
tier(4, 80, 149)
tier(8, 150, 199)
tier(12, 200, 234)
windows(0, 0, 79)
windows(4, 80, 149)
windows(8, 150, 199)
windows(12, 200, 234)

box(vec3(15, 1, 0), vec3(20, 6, 1), eraser) # grand entrance
box(vec3(16, 235, -16), vec3(19, 249, -19), white) # crown
box(vec3(17, 250, -17), vec3(18, 269, -18), black) # needle
