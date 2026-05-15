name wall_segment(length = 10, height = 5, color = black)
if not is_instance:
  show = false
  quit()
speed = 0
fill_box(0, 0, 0, length, height, 1, color)
var x = 0
while x < length:
  fill_box(x, height + 1, 0, x, height + 2, 1, color)
  x += 3
