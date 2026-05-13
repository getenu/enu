name tree(height = 6, trunk_color = brown, leaf_color = green)
if not is_instance:
  show = false
  quit()
speed = 0
fill_box(0, 0, 0, 0, height, 0, trunk_color)
fill_box(-2, height - 1, -2, 2, height + 1, 2, leaf_color)
