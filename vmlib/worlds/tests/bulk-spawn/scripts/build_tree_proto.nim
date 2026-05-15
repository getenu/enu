name tree(height = 8, trunk_color = brown, leaf_color = green)
if not is_instance:
  show = false
  quit()
speed = 0
fill_cylinder(0, 0, height - 3, 0, 0.6, trunk_color)
fill_sphere(0, height, 0, 3.0, leaf_color)
