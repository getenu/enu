name banner(height = 8, pole_color = black, flag_color = red)
if not is_instance:
  show = false
  quit()
speed = 0
fill_box(0, 0, 0, 0, height, 0, pole_color)
fill_box(1, height, 0, 3, height - 3, 0, flag_color)
