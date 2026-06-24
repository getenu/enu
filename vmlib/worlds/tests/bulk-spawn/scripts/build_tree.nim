name tree(height = 8, trunk_color = brown, leaf_color = green)
if not is_instance:
  show = false
  quit()
speed = 0
cylinder(size = 1.2, height = abs((height - 3) - (0)) + 1, at = vec3(0, min(0, height - 3), 0), color = me.trunk_color)
sphere(size = 6, at = vec3(0, height, 0), color = me.leaf_color)
