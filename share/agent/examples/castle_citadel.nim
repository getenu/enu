# Grand citadel (~56 m, ornate): a moated concentric fortress. Outer
# crenellated wall ringed by cone-roofed towers, twin-towered gatehouse
# with portcullis, stepped central keep with trim courses and arrow
# slits, crowned by a spire and banner. The most composition-heavy
# example: small procs (merlons/spire/banner/round_tower/tier) reused
# everywhere. NB: locals avoid reserved accessor names — `rad`/`tall`,
# never `radius`/`height`/`width` (those resolve to unit accessors).
let stone = brown
let trim = white
let dark = black

proc merlons(x1, z1, x2, z2, y: int, col: Colors) =
  if x1 == x2:
    var i = 0
    for z in min(z1, z2) .. max(z1, z2):
      if i mod 2 == 0:
        place(x1, y, z, col)
      inc i
  else:
    var i = 0
    for x in min(x1, x2) .. max(x1, x2):
      if i mod 2 == 0:
        place(x, y, z1, col)
      inc i

proc spire(cx, cz, base_y, rad, tall: int, col: Colors) =
  for i in 0 .. tall:
    let r = rad.float * (1.0 - i.float / tall.float)
    cylinder(size = max(r, 0.0) * 2.0, height = 1, at = vec3(cx, base_y + i, cz), color = col)

proc banner(cx, cz, y: int, col: Colors) =
  box(vec3(cx, y, cz), vec3(cx, y + 6, cz), dark)
  box(vec3(cx + 1, y + 4, cz), vec3(cx + 3, y + 6, cz), col)

proc round_tower(cx, cz, h, rad: int, roof: Colors) =
  cylinder(size = rad.float * 2.0, height = h + 1, at = vec3(cx, 0, cz), color = stone)
  place(cx + rad, h - 4, cz, dark)
  place(cx - rad, h - 4, cz, dark)
  place(cx, h - 4, cz + rad, dark)
  let cone = (rad + 1) * 2
  spire(cx, cz, h + 1, rad + 1, cone, roof)
  banner(cx, cz, h + 1 + cone, roof)

proc tier(x0, z0, x1, z1, top: int) =
  box(vec3(x0, 0, z0), vec3(x1, top, z1), stone)
  box(vec3(x0, top - 1, z0), vec3(x1, top - 1, z1), trim)
  merlons(x0, z0, x1, z0, top + 1, stone)
  merlons(x0, z1, x1, z1, top + 1, stone)
  merlons(x0, z0, x0, z1, top + 1, stone)
  merlons(x1, z0, x1, z1, top + 1, stone)
  let my = top div 2
  place(x0, my, (z0 + z1) div 2, dark)
  place(x1, my, (z0 + z1) div 2, dark)
  place((x0 + x1) div 2, my, z0, dark)
  place((x0 + x1) div 2, my, z1, dark)

# moat (water ring at ground level), gap at the gate
box(vec3(0, 0, 0), vec3(48, 0, 1), blue)
box(vec3(0, 0, 0), vec3(1, 0, 48), blue)
box(vec3(47, 0, 0), vec3(48, 0, 48), blue)
box(vec3(0, 0, 47), vec3(19, 0, 48), blue)
box(vec3(29, 0, 47), vec3(48, 0, 48), blue)

# outer curtain wall, crenellated, gate at x 20..28
let wt = 10
box(vec3(2, 0, 2), vec3(46, wt, 2), stone)
box(vec3(2, 0, 2), vec3(2, wt, 46), stone)
box(vec3(46, 0, 2), vec3(46, wt, 46), stone)
box(vec3(2, 0, 46), vec3(20, wt, 46), stone)
box(vec3(28, 0, 46), vec3(46, wt, 46), stone)
box(vec3(20, wt - 2, 46), vec3(28, wt, 46), stone) # arch
box(vec3(20, 0, 46), vec3(28, 6, 46), dark) # portcullis
merlons(2, 2, 46, 2, wt + 1, stone)
merlons(2, 2, 2, 46, wt + 1, stone)
merlons(46, 2, 46, 46, wt + 1, stone)
merlons(2, 46, 20, 46, wt + 1, stone)
merlons(28, 46, 46, 46, wt + 1, stone)

round_tower(2, 2, 17, 4, blue)
round_tower(46, 2, 17, 4, blue)
round_tower(2, 46, 17, 4, blue)
round_tower(46, 46, 17, 4, blue)
round_tower(24, 2, 13, 3, red) # mid-wall bartizans
round_tower(2, 24, 13, 3, red)
round_tower(46, 24, 13, 3, red)
round_tower(18, 46, 20, 4, blue) # gatehouse twins
round_tower(30, 46, 20, 4, blue)

# stepped central keep + corner turrets + crowning spire
tier(16, 16, 32, 32, 18)
tier(18, 18, 30, 30, 26)
tier(20, 20, 28, 28, 32)
round_tower(20, 20, 34, 2, red)
round_tower(28, 20, 34, 2, red)
round_tower(20, 28, 34, 2, red)
round_tower(28, 28, 34, 2, red)
spire(24, 24, 33, 5, 16, blue)
banner(24, 24, 49, red)
