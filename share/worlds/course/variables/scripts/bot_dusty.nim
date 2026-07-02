# Dusty: the canyon greeter. (Prototype narration — placeholder beats.)
lock = true
color = brown
turn 180 # face the ramp

say "- Howdy! I'm Dusty.",
  """
  # Welcome to **Redrock Canyon**

  Out here, one number changes everything.

  - The **water tower** needs taller legs — change one number.
  - The **bridge** across the gorge needs more planks — change
    one number.

  That's what a **variable** is: a name for a number, written once,
  used everywhere. Change it in one place and the whole build follows.
  """,
  width = 3.0

# Code tool only in course levels.
player.tools.incl CodeMode
player.tool = CodeMode
