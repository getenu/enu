# Greeter bot (id must start with bot_): wanders near its post, greets
# the player with a speech bubble + markdown sign when they come close,
# then goes back to wandering. Shows bot state machines, tethering, and
# say-with-sign in one small script.
color = green
speed = 3

-wander:
  forward 2 .. 6
  turn -60.0 .. 60.0

-come_home:
  turn start_position
  forward 4

-greet:
  turn player
  say "Welcome!",
    """
  # Hello

  I'm a scripted bot. Look around — everything here was built by
  scripts.
  """
  sleep 6

loop:
  nil -> wander
  if start_position.far(12):
    wander -> come_home
  if start_position.near(4):
    come_home -> wander
  if player.near(8):
    (wander, come_home) ==> greet
  greet -> wander
