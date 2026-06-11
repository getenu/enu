name wall_segment(length = 10, height = 5, color = black)
if not is_instance:
  show = false
  quit()
speed = 0
box(vec3(0, 0, 0), vec3(length, height, 1), color)
var x = 0
while x < length:
  box(vec3(x, height + 1, 0), vec3(x, height + 2, 1), color)
  x += 3
