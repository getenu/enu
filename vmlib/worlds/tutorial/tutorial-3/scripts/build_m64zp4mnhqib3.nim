name Button(door = Door, pause = 11.0, ghost = inky)
move me

loop:
  nil -> up(home + 0.2)
  if player.hit:
    up -> down(home + 0.2):
      door.open = true
      ghost.charge_player = true
  else:
    sleep -> up(home + 0.2):
      door.open = false
  down -> sleep(pause)
  glow = cycle(0.0, 0.05)
