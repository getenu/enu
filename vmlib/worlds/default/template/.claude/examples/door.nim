# Sliding door prototype. An instance slides open when something sets
# `open = true` — see doorway.nim for the wall + Button wiring.
# Don't declare a `color` proto param: `.new()` already has a built-in
# `color` (default eraser), the proto's param is silently dropped, and a
# turtle-drawn instance paints its whole shape in eraser — invisible.
# Callers pass `color = ...` to `.new()` instead.
name Door(open = false, door_width = 6, door_height = 8)

let dw = door_width
let dh = door_height

dh.times:
  right dw
  turn 180
  up 1

move me
scale = 1.05
forward 0.05 # offset from the wall plane to prevent z-fighting
speed = 5

loop:
  nil -> sleep as door_closed
  if open:
    door_closed -> left(home + door_width) as door_open
  else:
    door_open -> right(home) as door_closed
