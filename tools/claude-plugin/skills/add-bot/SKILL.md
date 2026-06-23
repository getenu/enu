---
description: Create bots (NPC robots) with behavior in an Enu level — wandering, chasing the player, speaking, and state-machine AI. Use when adding a bot or NPC.
---

# Add a Bot

Create a bot (NPC robot) with behavior. Bots can wander, chase players, say
things, and run complex state-machine AI.

## Usage

```
/add-bot <description>
```

## Files Needed

**`data/<name>/<name>.json`** — world position:
```json
{
  "id": "bot_guard",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [5.0, 0.0, -15.0]
  },
  "start_color": "GREEN",
  "edits": {}
}
```

**`scripts/<name>.nim`** — behavior script

Touch both files; Enu loads them and manages `level.json` itself.
A complete verified bot (wander + tether + greet with a markdown sign)
is at `${CLAUDE_PLUGIN_ROOT}/examples/bot_greeter.nim`.

## Bot API

```nim
color = green          # bot color
speed = 3              # movement speed (1=walk, 5=run)

forward 10             # move forward 10 units
turn right             # turn 90° right
turn player            # face the player
turn -player           # face away from player

say "Hello!"                        # speech bubble (plain text)
say "Short", "# Full Markdown\n..."  # short + detailed sign
say "text", width = 2.0             # wider sign

player.near(10)        # true if player is within 10 units
player.far(20)         # true if player is beyond 20 units
start_position.near(30) # true if close to spawn point
position               # current Vector3 position
start_position         # spawn Vector3 position
```

## Behavior Patterns

### Simple wanderer
```nim
color = blue
speed = 2

forever:
  forward 3 .. 10
  turn -45 .. 45
  sleep 1 .. 3
```

### Player-following guide
```nim
color = green
speed = 3

forever:
  turn player
  if player.near(15) and player.far(3):
    forward 1
  else:
    sleep 0.5
```

### Chaser with state machine
```nim
color = red
speed = 3

-wander:
  forward 2 .. 8
  turn -60 .. 60

-chase:
  turn player
  forward 5

-caught:
  say "Got you!"
  sleep 3

loop:
  nil -> wander
  caught -> wander

  if player.near(12) and start_position.near(30):
    wander ==> chase do:
      say "Hey!"
  if player.far(20):
    chase -> wander
  if player.near(2):
    chase -> caught
```

### Patrol between waypoints
```nim
color = brown
speed = 3

let waypoints = [
  (5.0, 0.0, -10.0),
  (5.0, 0.0, -30.0),
  (-5.0, 0.0, -30.0),
  (-5.0, 0.0, -10.0),
]
var wp = 0

forever:
  let target = waypoints[wp]
  turn(target)
  let dist = position.distance_to(target)
  forward dist
  wp = (wp + 1) mod waypoints.len
  sleep 1
```

### Guard with alert states
```nim
color = white
var alert = false

-idle:
  turn -30 .. 30
  sleep 2 .. 4

-alerted:
  say "Who goes there?"
  sleep 2
  alert = false

-chase:
  speed = 6
  turn player
  forward 3

loop:
  nil -> idle
  if player.near(8):
    (idle, alerted) ==> chase
  if player.far(25) or start_position.far(40):
    chase -> idle

  if player.near(15) and not alert:
    idle ==> alerted do:
      alert = true
      say "!", width = 0.5
```

### Shopkeeper / info bot (stationary)
```nim
lock = true
color = blue

turn 180    # face the player spawn direction

say "- Talk to me",
  """
  # Welcome!

  I'm a helpful bot. Here's what I can tell you:

  - Move with WASD
  - Jump with Space
  - Press ESC to close this panel

  [Click here for more](<nim://load_level("tutorial-1")>)
  """,
  width = 2.0, height = 3.0

forever:
  turn player   # keep facing the player
  sleep 0.5
```

### Bot that reacts to builds being touched
```nim
color = green
speed = 2

forever:
  # Check if the player is inside a specific build
  for build in Build.all:
    if build.id == "build_trigger_zone" and build.hit(player):
      say "You found the secret!"
      sleep 3
  turn player
  sleep 0.5
```

## Multiple Bots

Spawn copies of a bot prototype:

```nim
# In bot_soldier.nim:
name Soldier(patrol_z = -20.0)
color = white
speed = 3

forever:
  if position.z < patrol_z - 10:
    turn right
  elif position.z > patrol_z:
    turn left
  forward 2

# In a spawner script:
drawing = false
5.times(i):
  Soldier.new(patrol_z = -10.0 - i.float * 8.0)
```

## Signs from Bots

```nim
# Short text (always visible bubble)
say "Hello!"

# Short + detailed (click for more)
say "- Click me", "# Details\n\nFull markdown content here."

# Update sign content dynamically
sign.more = "# Updated\n\nNew content"

# Hide/show sign
sign.show = false
```
