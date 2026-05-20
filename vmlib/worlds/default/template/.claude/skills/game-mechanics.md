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

# Hit detection in a loop
loop:
  nil -> idle
  -idle:
    if Player.hit as p:
      say "Touched!"
      p.velocity = p.velocity + (0.0, 10.0, 0.0)  # bounce up
      sleep 1
```

## Collectible (disappears when touched)

```nim
# scripts/build_coin.nim
name Coin

speed = 0
color = yellow  # use white or green as proxy

# Draw the coin shape
fill_sphere(2, 2, 2, 1.5, green)

move me
speed = 20
var t = 0.0
var collected = false

forever:
  t += 0.05
  if not collected:
    turn right, 2.0   # spin
    if Player.hit:
      collected = true
      show = false
      echo "Coin collected!"
  sleep()
```

## Counter / Score Display

Use a bot to show a dynamic score:

```nim
# scripts/bot_score.nim
lock = true
color = white
speed = 0

var score* = 0  # exported so other scripts can increment it

forever:
  say \"""Score: {score}""", width = 2.0
  sleep 0.5
```

Another script increments it:
```nim
# Access exported var from score bot
for bot in Bot.all:
  if bot.name == "bot_score":
    # Can't directly access vars, but can use global state
    discard
```

## Win Condition

```nim
# scripts/build_win_zone.nim
name WinSpot

speed = 0
show = false   # invisible trigger zone
fill_box(0, 0, 0, 4, 4, 4, eraser)   # make it hollow so player can enter

loop:
  nil -> waiting
  -waiting:
    if Player.hit as p:
      p.playing = true
      # Show win sign
      say "- You Win!",
        """
        # Congratulations!

        You completed the level!

        [Play Again](<nim://reset_level()>)
        [Next Level](<nim://press_action("next_level")>)
        """,
        width = 3.0
```

## Player Physics Boosts

```nim
# Speed boost pad
loop:
  nil -> idle
  -idle:
    if Player.hit as p:
      p.velocity = p.velocity + (0.0, 0.0, -20.0)  # launch forward
      sleep 0.5

# Bounce pad
loop:
  nil -> idle
  -idle:
    if Player.hit as p:
      p.bounce(3.0)  # launch upward (power multiplier)
      sleep 0.5

# Slippery floor (reduce friction by moving player)
forever:
  if Player.hit as p:
    p.velocity = p.velocity + (p.velocity.x * 0.1, 0.0, p.velocity.z * 0.1)
  sleep()
```

## Door + Button System

```nim
# scripts/build_door1.nim
name Door(open = false, width = 12, height = 8)
speed = 0
color = brown

height.times:
  right width
  turn 180
  up 1

move me
speed = 8

loop:
  nil -> sleep as door_closed
  if open:
    door_closed -> left(home + width) as door_open
  else:
    door_open -> right(home) as door_closed
```

```nim
# scripts/build_button1.nim
var door1* = Door.new(width = 12, height = 8, color = brown)

name Button(door: Door = nil, pause = 0)
speed = 0
color = red
fill_box(0, 0, 0, 1, 0, 1, red)  # flat button on floor

move me
speed = 10

loop:
  nil -> sleep as waiting
  -waiting:
    if Player.hit:
      if door != nil:
        door.open = true
      color = green
      if pause > 0:
        sleep pause
        door.open = false
        color = red
```

```nim
# scripts/build_button1_instance.nim
Button.new(door = door1, pause = 5)
```

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
  # Reset player position
  if Player.hit as p:
    p.position = p.start_position
  sleep 2

loop:
  nil -> wander
  (wander, hit_player) -> chase if player.near(15)
  chase -> wander if player.far(30)
  chase -> hit_player if player.near(2)
```

## Checkpoint System

```nim
# scripts/build_checkpoint.nim
name Checkpoint

speed = 0
color = blue
fill_box(0, 0, 0, 3, 5, 0, blue)  # visible marker

var activated* = false

loop:
  nil -> waiting
  -waiting:
    if Player.hit as p:
      if not activated:
        activated = true
        color = green
        say "- Checkpoint!", "# Checkpoint Reached!\n\nProgress saved."
        sleep 3
        sign.show = false
```

## Timed Challenge

```nim
# scripts/bot_timer.nim
lock = true
color = white
speed = 0
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
speed = 0
show = false

var wave = 0

-spawn:
  wave += 1
  say \"""Wave {wave}""", width = 1.5
  let count = wave * 2
  count.times(i):
    soldier.new()
    sleep 0.5
  sleep 10

loop:
  nil -> spawn
  spawn -> spawn  # immediately re-enter spawn after done
```
