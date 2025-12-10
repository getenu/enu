lock = true
# Main sign - Exercise A
save()
color = black
5.times:
  up 10
  left 1
  down 10
  left 1
restore()
let main_overview = """
# Bot/Animation Station
**Difficulty**: *** (Hardest)

## Exercise A: Circle Walker
"""

let exercise_a = """
Make a bot walk in a circle!

```nim
speed = 3

10.times:
  forward 5
  turn 36
```

**Try these extensions:**
- Bigger circle: Change `turn 36` to `turn 10`
- Square walker: Use `4.times` and `turn 90`
- **Forever loop**: Replace `10.times` with `forever` (bot keeps going!)
"""

let main_sign = say(main_overview, exercise_a, width = 10, height = 4, size = 520)
main_sign.position = main_sign.position + (UP * 5) + (FORWARD * 0.5)

# Exercise B sign
let exercise_b_content = """
## Exercise B: Dancing Bot

Bot that walks and spins with random movements!

```nim
speed = 3

forever:
  forward 10
  turn random(30, 60, 90)
  say "Wheee!"
```

**Try these extensions:**
- Change the message: `say "I love coding!"`
- Rainbow bot: Add `color = cycle(red, blue, green)`
- Random speed: Try `speed = 1..5`
"""

let sign_b = say("# B", exercise_b_content, width = 2.0, height = 2.0, size = 1000)
sign_b.position = me.position + (UP * 4) + (LEFT * 1) + (FORWARD * 0.5)

# Exercise C sign
let exercise_c_content = """
## Exercise C: Follow Bot (Advanced!)

Bot that follows the player!

```nim
speed = 2

forever:
  turn player
  forward 2

  if player.near(30):
    say "Hello friend!"
```

**Try these extensions:**
- Change the distance: Try `player.near(10)` or `player.near(50)`
- Different message: `say "Caught you!"`
- Run away: After `turn player`, add `turn 180` to run the opposite way!
"""

let sign_c = say("# C", exercise_c_content, width = 2.0, height = 2.0, size = 1000)
sign_c.position = me.position + (UP * 4) + (LEFT * 5) + (FORWARD * 0.5)

# Help sign
let help_content = """
## Code Not Working?

1. ✓ Check spelling (`forward` not `foward`)
2. ✓ Check colon after `.times:` and `forever:`
3. ✓ Check indentation (2 spaces)
4. ✓ Still stuck! Raise your hand!
"""

let help_sign = say("# Help", help_content, width = 2.0, height = 1.0, size = 520)
help_sign.position = me.position + (UP * 1.5) + (LEFT * 3) + (FORWARD * 0.5)

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
