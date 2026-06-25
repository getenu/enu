show = false

let overview = """
# Art/Effects Station - Exercise B
**Difficulty**: ** (Medium)

Random Colors
"""

let details = """
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

---

[Back to Station Menu](<nim://show_exercise("station_3_overview")>)
[Previous: Exercise A](<nim://show_exercise("station_3_a")>)
[Next: Exercise C](<nim://show_exercise("station_3_c")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
