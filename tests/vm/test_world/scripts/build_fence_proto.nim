name fence_post(height = 3, color = brown)
if not is_instance:
  show = false
  quit()
speed = 0
box(vec3(0, 0, 0), vec3(0, height, 0), color)
box(vec3(0, height - 1, -1), vec3(0, height - 1, 1), color)
