let menu* = me

speed = 0
lock = true

let overview =
  \"""

World `{world_name()}`

Level `{level_name()}`

"""

let details =
  \"""

# Menu

Welcome to level `{level_name()}` of world `{world_name()}`.

- [Next Level](<nim://press_action("next_level")>)

- [Previous Level](<nim://press_action("prev_level")>)

- [Help](https://ē.nu/docs/intro.html)

- [Load Tutorial](<nim://load_level("tutorial-1", "tutorial")>)

- [Load Examples](<nim://load_level("tutorial-2", "tutorial")>)

- [Reset Level](<nim://reset_level()>)

"""

turn 180
up 5
right 3
forward 1
lean forward, 20
say overview, details, height = 2, width = 6, size = 610

move me
forever:
  turn -player
  sleep()
