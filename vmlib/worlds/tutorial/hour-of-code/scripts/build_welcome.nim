lock = true
let overview = \"""
# Welcome to Enu Hour of Code!

You are **Player {player.number}**

## Controls
- **WASD**: Move around
- **Space x2**: Fly (press again to land)
- **Alt/Option + Click**: Open code editor
"""

let details = """
## Today's Activities

### Guided Exercises (Everyone Together)
1. **Draw a Shape** - Learn loops and movement
2. **Build a Tower** - Create 3D structures

### Choose Your Own Adventure
Then explore 3 stations:
- **Building Station** ⭐ (Easiest)
- **Art/Effects Station** ⭐⭐
- **Bot/Animation Station** ⭐⭐⭐

## Getting Started
1. Listen to your teacher
2. Work with your partner
3. Have fun coding!

## Need Help?
Check the Debug Checklist at each station or raise your hand!
"""

say overview, details, width = 10, height = 4, size = 520

move me
forever:
  follow_nearest_player(me)
  sleep 0.5
