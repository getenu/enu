name hay_bale(size = 3, color = brown)
if not is_instance:
  show = false
  quit()
speed = 0
cylinder(size = (size.float) * 2.0, height = abs((size) - (0)) + 1, at = vec3(0, min(0, size), 0), color = me.color)
