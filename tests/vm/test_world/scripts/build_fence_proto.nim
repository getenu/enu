name fence_post(height = 3, color = brown)
if not is_instance:
  show = false
  quit()
speed = 0
fill_box(0, 0, 0, 0, height, 0, color)
fill_box(0, height - 1, -1, 0, height - 1, 1, color)
