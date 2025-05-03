loop:
  if ?player and player.hit:
    player.bounce(4)
    inky.charge_player = true
