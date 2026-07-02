# The road from the beach to the lighthouse. Black surface with a dashed
# white centerline — the dashes drawn by a loop, naturally.
lock = true
speed = 0
color = black

box(vec3(-1, 0, 0), vec3(1, 0, -38), color = black)
8.times(i):
  box(vec3(0, 0, -3 - i * 4), vec3(0, 0, -4 - i * 4), color = white)
