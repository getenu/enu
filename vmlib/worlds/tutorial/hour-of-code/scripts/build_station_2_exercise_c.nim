show = false

let overview = """
# Bot/Animation Station - Exercise C
**Difficulty**: *** (Hardest)

Follow Bot (Advanced!)
"""

let details = """
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

---

[Back to Station Menu](<nim://show_exercise("station_2_overview")>)
[Previous: Exercise B](<nim://show_exercise("station_2_b")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
