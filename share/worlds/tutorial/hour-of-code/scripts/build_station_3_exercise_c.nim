show = false

let overview = """
# Art/Effects Station - Exercise C
**Difficulty**: ** (Medium)

Your Masterpiece
"""

let details = """
## Exercise C: Your Masterpiece

Combine everything!

**Ideas to try:**
- What happens with `100.times` instead of `10.times`?
- Mix `random()` and `cycle()` together
- Add `glow`, `scale`, and `color` all together
- Go wild and create something unique!

---

[Back to Station Menu](<nim://show_exercise("station_3_overview")>)
[Previous: Exercise B](<nim://show_exercise("station_3_b")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
