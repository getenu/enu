let overview = """
# Building Station
**Difficulty**: * (Easiest)

Create amazing 3D structures!

## [?] Code Not Working?

1. ✓ Check spelling (`forward` not `foward`)
2. ✓ Check colon after `.times:`
3. ✓ Check indentation (2 spaces)
4. ✓ Still stuck? Raise your hand!
"""

let details = """
## Choose an Exercise

[Exercise A: Rainbow Tower](<nim://show_exercise("station_1_a")>)
Build on what you learned in the guided exercises.

[Exercise B: Pattern Builder](<nim://show_exercise("station_1_b")>)
Build stairs and other patterns!

[Exercise C: Free Build](<nim://show_exercise("station_1_c")>)
Combine everything you've learned!
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
