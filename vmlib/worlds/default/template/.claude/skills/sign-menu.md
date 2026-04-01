# Signs and Menus

Create informational signs, menus with clickable links, and interactive panels.
Signs can be attached to any unit (build or bot) and support full Markdown.

## Usage

```
/sign-menu <description>
```

## Basic Sign Syntax

```nim
# Simple speech bubble
say "Hello, world!"

# Short text + detailed panel (click to expand)
say "- Click me", "# Title\n\nMarkdown content."

# Named parameters
say "text", "more", width = 2.0, height = 3.0, size = 32
```

Parameters:
- `width` — panel width multiplier (default 1.0)
- `height` — panel height multiplier (default 1.0)
- `size` — font size in pixels (default 32)
- `billboard = true` — always face the player

## Stationary Info Sign (Build)

```json
// data/build_sign_welcome/build_sign_welcome.json
{
  "id": "build_sign_welcome",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [0.0, 2.0, -5.0]
  },
  "start_color": "BROWN",
  "edits": {}
}
```

```nim
# scripts/build_sign_welcome.nim
lock = true
speed = 0
turn 180    # face toward player spawn

let overview = "Welcome to my world!"
let details =
  """
  # Welcome!

  Explore this world and discover what's inside.

  - Move with `WASD`
  - Jump with `Space`
  - Fly by double-jumping

  Press `ESC` to close this panel.
  """

say overview, details, width = 3.0, height = 4.0
```

## Menu with Links

Nim links use `<nim://...>` syntax and can run any Nim expression:

```nim
let details =
  """
  # Main Menu

  - [Load Tutorial](<nim://load_level("tutorial-1", "tutorial")>)
  - [Reset Level](<nim://reset_level()>)
  - [Next Level](<nim://press_action("next_level")>)
  - [God Mode](<nim://player.god = true>)
  """

say "# Menu", details, width = 4.0, height = 5.0
```

## Dynamic Sign Content

Update sign content based on game state:

```nim
lock = true
speed = 0

var score = 0

forever:
  let text = \"""
  Score: {score}
  """
  say text, width = 2.0
  sleep 1
```

## Chained Tutorial Sign

Guide the player through steps:

```nim
lock = true
color = white
speed = 1
turn 180

-intro:
  say "- Welcome!",
    """
    # Welcome to this Level

    Explore and find the hidden gem.

    Sneak behind me to continue.
    """,
    width = 2.0
  while me.angle_to(player).abs notin 150 .. 210:
    sleep 0.5

-hint:
  say "- Getting closer...",
    """
    # Hint

    The gem is north of here (-Z direction).

    Keep going!
    """
  while player.far(50):
    sleep 1

-found:
  say "- You found it!", "# Congratulations!\n\nWell done!"
  sleep 5

move me
forever:
  turn -player
  sleep()

intro()
hint()
found()
```

## Level Menu Template

Standard level menu (shows on builds in default template):

```nim
let menu* = me
speed = 0
lock = true

let overview = \"""
World `{world_name()}`

Level `{level_name()}`
"""

let details = \"""
# Menu

- [Next Level](<nim://press_action("next_level")>)
- [Previous Level](<nim://press_action("prev_level")>)
- [Reset Level](<nim://reset_level()>)
- [Load Tutorial](<nim://load_level("tutorial-1", "tutorial")>)
"""

turn 180
up 5
lean forward, 20
say overview, details, height = 2, width = 6, size = 610

move me
forever:
  turn -player
  sleep()
```

## Sign Properties

```nim
sign.show = true/false       # show or hide the sign
sign.open = true/false       # open or close the expanded panel
sign.more = "new content"    # update the detailed panel text
```

## Embedded Links Reference

| Action | Link |
|--------|------|
| Load level | `<nim://load_level("level-name")>` |
| Load level in world | `<nim://load_level("level", "world")>` |
| Reset level | `<nim://reset_level()>` |
| Next level | `<nim://press_action("next_level")>` |
| Previous level | `<nim://press_action("prev_level")>` |
| Enable god mode | `<nim://player.god = true>` |
| Enable player running | `<nim://player.running = true>` |
| Custom expression | `<nim://any_nim_expression>` |
| External URL | `https://...` |
