let overview = """
# Art/Effects Station
**Difficulty**: ** (Medium)

Create amazing visual art with randomness!

## [?] Code Not Working?

1. ✓ Check spelling (`forward` not `foward`)
2. ✓ Check colon after `.times:`
3. ✓ Check indentation (2 spaces)
4. ✓ Still stuck? Raise your hand!
"""

let details = """
## Choose an Exercise

[Exercise A: Spiral Pattern](<nim://show_exercise("station_3_a")>)
Create beautiful spirals!

[Exercise B: Random Colors](<nim://show_exercise("station_3_b")>)
Add randomness for unique art!

[Exercise C: Your Masterpiece](<nim://show_exercise("station_3_c")>)
Combine everything!
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
