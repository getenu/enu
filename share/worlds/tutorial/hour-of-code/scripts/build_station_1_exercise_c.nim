show = false

let overview = """
# Building Station - Exercise C
**Difficulty**: * (Easiest)

Free Build
"""

let details = """
## Exercise C: Free Build

Combine everything you've learned!

- Try different shapes (triangles with `3.times`)
- Make circles (use `turn 36` for smooth curves)
- Build a house, castle, or bridge
- Use your imagination!

---

[Back to Station Menu](<nim://show_exercise("station_1_overview")>)
[Previous: Exercise B](<nim://show_exercise("station_1_b")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
