player = nil

loop:
  if Player.hit as p:
    player = p
    player.playing = true
    player.running = true
