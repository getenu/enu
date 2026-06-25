show = false

let overview = """
# Bot/Animation Station - Exercise A
**Difficulty**: *** (Hardest)

Circle Walker
"""

let details = """
## Exercise A: Circle Walker

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

---

[Back to Station Menu](<nim://show_exercise("station_2_overview")>)
[Next: Exercise B](<nim://show_exercise("station_2_b")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
