show = false

let overview = """
# Building Station - Exercise A
**Difficulty**: * (Easiest)

Rainbow Tower
"""

let details = """
## Exercise A: Rainbow Tower

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

---

[Back to Station Menu](<nim://show_exercise("station_1_overview")>)
[Next: Exercise B](<nim://show_exercise("station_1_b")>)
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
