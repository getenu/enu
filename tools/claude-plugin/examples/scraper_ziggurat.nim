# Hanging-gardens ziggurat (~105 m): hollow tiers stepping inward, every
# terrace edged with a green garden lip and a row of windows per face,
# topped with a green dome.
let base = 40
var y0 = 0
var inset = 0
while base - inset * 2 > 8:
  let s = inset
  let e = base - inset
  box(vec3(s, y0, -s), vec3(e, y0 + 11, -e), brown, fill = false)
  box(vec3(s, y0 + 12, -s), vec3(e, y0 + 12, -(s + 1)), green)
  box(vec3(s, y0 + 12, -(e - 1)), vec3(e, y0 + 12, -e), green)
  box(vec3(s, y0 + 12, -s), vec3(s + 1, y0 + 12, -e), green)
  box(vec3(e - 1, y0 + 12, -s), vec3(e, y0 + 12, -e), green)
  var w = s + 3
  while w < e - 2:
    box(vec3(w, y0 + 5, -s), vec3(w + 1, y0 + 7, -s), eraser)
    box(vec3(w, y0 + 5, -e), vec3(w + 1, y0 + 7, -e), eraser)
    box(vec3(s, y0 + 5, -w), vec3(s, y0 + 7, -(w + 1)), eraser)
    box(vec3(e, y0 + 5, -w), vec3(e, y0 + 7, -(w + 1)), eraser)
    w += 4
  inset += 2
  y0 += 12

sphere(size = 9, at = vec3(20, (y0 + 2).float, -20), color = green)
