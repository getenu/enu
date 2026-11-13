name ReloadDoor(open = false, door_width = 6, door_height = 8)
speed = 0
door_height.times:
  right door_width
  turn 180
  up 1
