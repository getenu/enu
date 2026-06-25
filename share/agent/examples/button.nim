# Button prototype: pops its linked door open for `pause` seconds when
# the player hits it. The default for a proto-typed param is the proto
# object itself (`door = Door`). State procs are defined BEFORE the loop.
name Button(door = Door, pause = 5)

box(width = 2, height = 1, depth = 2, color = red) # flat pad, not a cube

move me
speed = 10

-press:
  door.open = true
  color = green
  sleep pause
  door.open = false
  color = red

loop:
  nil -> sleep as idle
  if Player.hit:
    idle -> press
  press -> sleep as idle
