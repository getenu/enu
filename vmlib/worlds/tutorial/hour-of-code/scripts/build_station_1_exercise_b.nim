show = false

let overview = """
# Building Station - Exercise B
**Difficulty**: * (Easiest)

Pattern Builder
"""

let details = """
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

---

[Back to Station Menu](<nim://show_exercise("station_1_overview")>)
[Previous: Exercise A](<nim://show_exercise("station_1_a")>)
[Next: Exercise C](<nim://show_exercise("station_1_c")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
