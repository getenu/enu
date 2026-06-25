# Polygon Tower prototype: walk an N-gon, over-turning by `twist` per
# corner so the shaft rotates as it rises. The cleanest proto + spawner
# pair — see tower_cluster.nim for randomised instantiation.
# Capture params into locals before the draw loop.
name Tower(height = 40, sides = 5, length = 8, twist = 2.0, color = brown)

let h = height
let s = sides
let len = length
let tw = twist
let col = color
color = col

h.times:
  s.times:
    forward len
    turn 360.0 / s.float + tw
  up 1
