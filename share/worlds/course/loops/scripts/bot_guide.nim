# Stationary guide. Says hello and sends the player down the path — the
# level-1 intro pattern: a friendly face, then the visual path does the
# guiding (no follow-me bot).
lock = true
color = blue
turn 180 # face the spawning player

say "- Hi! I'm Pip.",
  """
  # Welcome to **Loops** Island!

  Here you'll learn one of coding's most useful tricks: how to make
  the computer **repeat** things for you.

  Follow the blue path when you're ready. →
  """,
  width = 3.0
