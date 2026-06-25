---
description: Add Enu gameplay systems: collectibles, triggers, score displays, win conditions, and player physics boosts. Use when adding interactive game mechanics.
---

# Game Mechanics

Add gameplay systems: collectibles, triggers, score displays, win conditions,
player physics boosts, and other interactive elements.

## Usage

```
/game-mechanics <description>
```

## Player Detection

```nim
# Check if player is inside a build's volume
if Player.hit as p:
  # p is the Player that's inside this build
  p.running = true

# Check if player is near a position
if player.near(5):
  say "You're close!"

# Hit detection in a state loop (state procs go BEFORE the loop)
-idle:
  if Player.hit as p:
    say "Touched!"
    p.velocity = p.velocity + (0.0, 10.0, 0.0)  # bounce up
    sleep 1

loop:
  nil -> idle
```

## Collectible (disappears when touched)

Verified script: `.claude/examples/coin.nim`.

```nim
sphere(size = 3, color = green)

move me
speed = 20
var collected = false

forever:
  if not collected:
    turn right, 5.0   # spinning yields on its own
    if Player.hit:
      collected = true
      show = false
      echo "Coin collected!"
  else:
    sleep 1           # idle branch needs a duration sleep
```

## Counter / Score Display

Use a bot to show a dynamic score:

```nim
# scripts/bot_score.nim
lock = true
color = white

var score* = 0  # exported so other scripts can increment it

forever:
  say \"""Score: {score}""", width = 2.0
  sleep 0.5
```

## Win Condition

```nim
# scripts/build_win_zone.nim
name WinSpot

show = false   # invisible trigger zone
box(width = 5, height = 5, depth = 5, color = eraser)   # hollow so player can enter

-waiting:
  if Player.hit as p:
    p.playing = true
    say "- You Win!",
      """
      # Congratulations!

      You completed the level!

      [Play Again](<nim://reset_level()>)
      [Next Level](<nim://press_action("next_level")>)
      """,
      width = 3.0

loop:
  nil -> waiting
```

## Player Physics Boosts

```nim
# Speed boost pad
-idle:
  if Player.hit as p:
    p.velocity = p.velocity + (0.0, 0.0, -20.0)  # launch forward
    sleep 0.5

loop:
  nil -> idle
```

```nim
# Bounce pad
-idle:
  if Player.hit as p:
    p.bounce(3.0)  # launch upward (power multiplier)
    sleep 0.5

loop:
  nil -> idle
```

## Door + Button System

The verified, wired system lives in `.claude/examples/`:
`door.nim` (sliding pocket door), `button.nim` (player-pressed,
auto-closing), `doorway.nim` (the wall + spawner that links them with
`Button.new(door = d, ...)`). The traps it encodes:

- A proto-typed param defaults to the proto object: `name Button(door = Door, pause = 5)`.
- Don't declare a `color` proto param; pass `color = ...` to `.new()`
  (its built-in default is eraser — a turtle-drawn instance would paint
  invisibly).
- State procs (`-press:`) are defined before the `loop:`.
- Nudge the door a fraction of a voxel off the wall plane to avoid
  z-fighting.

Open a door from anywhere that holds a reference: `d.open = true`.

## Enemy / Hazard

```nim
# scripts/bot_hazard.nim
color = red
speed = 4

-wander:
  forward 2 .. 8
  turn -45 .. 45

-chase:
  turn player
  forward 3

-hit_player:
  say "Zap!"
  if Player.hit as p:
    p.position = p.start_position  # send them back
  sleep 2

loop:
  nil -> wander
  if player.near(15):
    (wander, hit_player) ==> chase
  if player.far(30):
    chase -> wander
  if player.near(2):
    chase -> hit_player
```

## Checkpoint System

```nim
# scripts/build_checkpoint.nim
name Checkpoint

color = blue
box(width = 4, height = 6, depth = 1, color = blue)  # visible marker

var activated* = false

-waiting:
  if Player.hit as p:
    if not activated:
      activated = true
      color = green
      say "- Checkpoint!", "# Checkpoint Reached!\n\nProgress saved."
      sleep 3
      sign.show = false

loop:
  nil -> waiting
```

## Timed Challenge

```nim
# scripts/bot_timer.nim
lock = true
color = white
turn 180

var time_limit = 60  # seconds
var running = false
var start_time = 0.0

forever:
  if running:
    let elapsed = now() - start_time
    let remaining = time_limit.float - elapsed
    if remaining <= 0:
      say "- Time's up!",  "# Time's Up!\n\nTry again."
      running = false
    else:
      say \"""Time: {remaining.int}s""", width = 1.5
  sleep 0.5
```

## Spawn Enemies Over Time

```nim
# scripts/build_spawner.nim
show = false

var wave = 0

-spawn:
  wave += 1
  say \"""Wave {wave}""", width = 1.5
  let count = wave * 2
  count.times(i):
    Soldier.new()
    sleep 0.5
  sleep 10

loop:
  nil -> spawn
  spawn -> spawn  # immediately re-enter after each wave
```
