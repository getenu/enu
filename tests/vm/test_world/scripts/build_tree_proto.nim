name tree(height = 6, trunk_color = brown, leaf_color = green)
if not is_instance:
  show = false
  quit()
speed = 0
box(vec3(0, 0, 0), vec3(0, height, 0), trunk_color)
box(vec3(-2, height - 1, -2), vec3(2, height + 1, 2), leaf_color)
