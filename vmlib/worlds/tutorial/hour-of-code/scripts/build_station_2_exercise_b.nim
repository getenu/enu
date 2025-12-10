show = false

let overview = """
# Bot/Animation Station - Exercise B
**Difficulty**: *** (Hardest)

Dancing Bot
"""

let details = """
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

---

[Back to Station Menu](<nim://show_exercise("station_2_overview")>)
[Previous: Exercise A](<nim://show_exercise("station_2_a")>)
[Next: Exercise C](<nim://show_exercise("station_2_c")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
