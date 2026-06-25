show = false

let overview = """
# Art/Effects Station - Exercise A
**Difficulty**: ** (Medium)

Spiral Pattern
"""

let details = """
## Exercise A: Spiral Pattern

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

---

[Back to Station Menu](<nim://show_exercise("station_3_overview")>)
[Next: Exercise B](<nim://show_exercise("station_3_b")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
