name start_spot

while maze.building:
  sleep 0.5

for player in Player.all:
  player.position = start_spot
  player.rotation = 180

loop:
  if Player.added as p:
    player.position = start_spot
    player.rotation = 180
