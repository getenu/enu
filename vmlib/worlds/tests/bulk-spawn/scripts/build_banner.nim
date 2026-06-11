name banner(height = 8, pole_color = black, flag_color = red)
if not is_instance:
  show = false
  quit()
speed = 0
box(vec3(0, 0, 0), vec3(0, height, 0), pole_color)
box(vec3(1, height, 0), vec3(3, height - 3, 0), flag_color)
