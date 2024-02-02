name inky(charge_player = false)
move me

-explore:
  speed = 3
  glow = 0
  scale = 1
  up home + 20
  if player.far(200):
    turn player
  else:
    turn -180 .. 180
  forward 5 .. 10

-attack:
  speed = 50
  position = position.fuzzed(2, 0, 2)
  turn player
  forward 2
  if player.near(20):
    down height - player.height

  scale = cycle(1.5, 1.8)
  glow = cycle(0, 1)

-charge:
  scale = 1
  speed = 20
  go player

-hunt:
  speed = 15
  if 1 in 10:
    turn player
  else:
    turn -180 .. 180
  forward 5 .. 10

-win_game:
  player.position = win_spot
  player.turn end_sign
  position = spin_spot
  scale = 1
  speed = 5
  player.playing = false
  30.times:
    turn right
    glow = cycle(1, 0)

-lose_game:
  player.position = lose_spot
  player.turn end_sign
  player.playing = false

loop:
  nil -> sleep
  if not maze.building:
    sleep -> explore
  if charge_player:
    (explore, hunt, attack) ==> charge
    charge_player = false

  if player.hit == UP:
    others ==> win_game
  elif player.hit:
    (others, -win_game) ==> lose_game

  if sees(player, 150):
    (hunt, explore) ==> attack
  else:
    attack -> charge
  charge -> hunt

  if player.far(60):
    hunt -> explore
  (win_game, lose_game) -> reset
  reset -> explore
