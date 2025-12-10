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
# Art/Effects Station
**Difficulty**: ** (Medium)

## Exercise A: Spiral Pattern
"""

let exercise_a = """
Create beautiful spirals!

```nim
speed = 0
color = cycle(red, blue, green)

10.times:
  forward 5
  turn 36  # Makes a circle!
```

**Try these extensions:**
- Add sparkle: Put `glow = 1` before the loop
- More spirals: Change `10.times` to `20.times`
- Different shapes: Try `turn 45` or `turn 20`
"""

let main_sign = say(main_overview, exercise_a, width = 10, height = 4, size = 520)
main_sign.position = main_sign.position + (UP * 5) + (FORWARD * 0.5)

# Exercise B sign
let exercise_b_content = """
## Exercise B: Random Colors

Add randomness for unique art!

```nim
speed = 0
up 5

10.times:
  forward 5
  turn 36
  color = random(red, blue, green, white)
  scale = cycle(1, 2, 3)
```

**Try these extensions:**
- Extra sparkle: Add `glow = 1` before the loop
- Random angles: Try `turn 1..50` (random turn!)
- Build upward: Add `up 1` inside the loop
"""

let sign_b = say("# B", exercise_b_content, width = 2.0, height = 2.0, size = 1000)
sign_b.position = me.position + (UP * 4) + (LEFT * 1) + (FORWARD * 0.5)

# Exercise C sign
let exercise_c_content = """
## Exercise C: Your Masterpiece

Combine everything!

**Ideas to try:**
- What happens with `100.times` instead of `10.times`?
- Mix `random()` and `cycle()` together
- Add `glow`, `scale`, and `color` all together
- Go wild and create something unique!
"""

let sign_c = say("# C", exercise_c_content, width = 2.0, height = 2.0, size = 1000)
sign_c.position = me.position + (UP * 4) + (LEFT * 5) + (FORWARD * 0.5)

# Help sign
let help_content = """
## Code Not Working?

1. ✓ Check spelling (`forward` not `foward`)
2. ✓ Check colon after `.times:`
3. ✓ Check indentation (2 spaces)
4. ✓ Still stuck? Raise your hand!
"""

let help_sign = say("# Help", help_content, width = 2.0, height = 1.0, size = 520)
help_sign.position = me.position + (UP * 1.5) + (LEFT * 3) + (FORWARD * 0.5)

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
