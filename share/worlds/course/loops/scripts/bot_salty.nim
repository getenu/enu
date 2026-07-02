# Salty: the bot puzzle. He can't swim — the player codes stepping stones
# across the channel, then he bumbles over them (falling into the gaps
# and climbing out) to reach Chest Island. He is his own checker.
lock = true
color = green
turn left # face west, toward the arriving player

say "- Help! I can't swim!",
  """
  # Salty's stuck!

  The flag chest is on that island, and Salty **melts in water**
  (don't ask).

  See the white pad at the water's edge? Open its code and lay
  **stepping stones** all the way across — with a loop.

  Stones don't have to touch! Salty is an *excellent* climber.
  """,
  width = 3.0

var crossed = false
forever:
  if not crossed:
    for b in Build.all:
      if b.id == "build_stones":
        let span = b.bounds.max.x - b.bounds.min.x
        if span >= 20.0:
          crossed = true
          echo "COURSE: stones span the channel - salty crossing"
          say "- Stones! Here I go!"
          sleep 1
          turn 180 # about-face: west -> east, toward the island
          speed = 2
          forward 27
          say "- I MADE it! Check the chest!", width = 2.0
          echo "COURSE: salty reached the island"
  sleep 0.5
