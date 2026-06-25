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
# Building Station
**Difficulty**: * (Easiest)

## Exercise A: Rainbow Tower
"""

let exercise_a = """
**Start here!** Build on what you learned in the guided exercises.

```nim
speed = 0
up 1

10.times:
  color = cycle(red, blue, green, white)
  4.times:
    forward 5
    turn right
  up 1
```

**Try these extensions:**
- Spiral tower: Add `turn 10` before `up 1`
- Make it bigger: Change `forward 5` to `forward 10`
- More colors: Add `, black, brown` after `white`
"""

let main_sign = say(main_overview, exercise_a, width = 10, height = 4, size = 520)
main_sign.position = main_sign.position + (UP * 5) + (FORWARD * 0.5)

# Exercise B sign
let exercise_b_content = """
## Exercise B: Pattern Builder

Build stairs and other patterns!

```nim
speed = 0
color = blue

5.times:
  forward 5
  up 1
```

**Try these extensions:**
- Longer stairs: Change `5.times` to `10.times`
- Rainbow stairs: `color = cycle(red, blue, green)`
- Multiple staircases side by side
"""

let sign_b = say("# B", exercise_b_content, width = 2.0, height = 2.0, size = 1000)
sign_b.position = me.position + (UP * 4) + (LEFT * 1) + (FORWARD * 0.5)

# Exercise C sign
let exercise_c_content = """
## Exercise C: Free Build

Combine everything you've learned!

- Try different shapes (triangles with `3.times`)
- Make circles (use `turn 36` for smooth curves)
- Build a house, castle, or bridge
- Use your imagination!
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
