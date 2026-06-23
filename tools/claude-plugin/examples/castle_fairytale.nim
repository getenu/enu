# Fairytale castle (~45 m): white round towers of varying heights with
# blue/red cone roofs and pennants, linked by curtain walls with a gate.
# Helper procs (spire/flag/tower) compose the scene; the cone is stacked
# 1-high disks of shrinking fractional diameter.
let body = white

proc spire(cx, cz, base_y, rad, tall: int, col: Colors) =
  for i in 0 .. tall:
    let r = rad.float * (1.0 - i.float / tall.float)
    cylinder(size = max(r, 0.0) * 2.0, height = 1, at = vec3(cx, base_y + i, cz), color = col)

proc flag(cx, cz, y: int, col: Colors) =
  box(vec3(cx, y, cz), vec3(cx, y + 5, cz), white)
  box(vec3(cx + 1, y + 3, cz), vec3(cx + 3, y + 4, cz), col)

proc tower(cx, cz, h, r: int, roof: Colors) =
  cylinder(size = r.float * 2.0, height = h + 1, at = vec3(cx, 0, cz), color = body)
  place(cx + r, h - 3, cz, blue)
  place(cx - r, h - 3, cz, blue)
  place(cx, h - 6, cz + r, blue)
  let cone_h = (r + 1) * 2
  spire(cx, cz, h + 1, r + 1, cone_h, roof)
  flag(cx, cz, h + 1 + cone_h, roof)

# curtain walls linking the corner towers, with a gate gap to the north
let lo = 6
let hi = 34
let wh = 7
box(vec3(lo, 0, lo), vec3(hi, wh, lo), body) # south
box(vec3(lo, 0, lo), vec3(lo, wh, hi), body) # west
box(vec3(hi, 0, lo), vec3(hi, wh, hi), body) # east
box(vec3(lo, 0, hi), vec3(16, wh, hi), body)
box(vec3(24, 0, hi), vec3(hi, wh, hi), body)
box(vec3(16, wh - 1, hi), vec3(24, wh, hi), body) # arch over the gate

tower(20, 20, 28, 4, blue) # grand central tower
tower(lo, lo, 15, 3, red)
tower(hi, lo, 19, 3, blue)
tower(lo, hi, 13, 3, red)
tower(hi, hi, 22, 3, red)
tower(13, hi, 10, 2, blue) # gate flankers
tower(27, hi, 11, 2, red)

# walls start at local 6, so the engine's default block at (0, 0, 0)
# would sit alone on open ground — erase it.
place(0, 0, 0, eraser)
