let overview = """
# Bot/Animation Station
**Difficulty**: *** (Hardest)

Program bots to move and interact!

## [?] Code Not Working?

1. ✓ Check spelling (`forward` not `foward`)
2. ✓ Check colon after `.times:` and `forever:`
3. ✓ Check indentation (2 spaces)
4. ✓ Still stuck? Raise your hand!
"""

let details = """
## Choose an Exercise

[Exercise A: Circle Walker](<nim://show_exercise("station_2_a")>)
Make a bot walk in a circle!

[Exercise B: Dancing Bot](<nim://show_exercise("station_2_b")>)
Bot that walks and spins with random movements!

[Exercise C: Follow Bot (Advanced!)](<nim://show_exercise("station_2_c")>)
Bot that follows the player!
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
