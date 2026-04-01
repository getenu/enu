Add a bot to this Enu level: $ARGUMENTS

Steps:
1. `get_level_dir` to get LEVEL_DIR, then `screenshot` to see the current state and choose a good spawn position
2. Pick a unique ID: `bot_<descriptive_name>` (lowercase, no spaces)
3. Create `LEVEL_DIR/data/<id>/<id>.json` — set `origin` to the world spawn position, `start_color`, and `"edits": {"<id>": []}`
4. Write `LEVEL_DIR/scripts/<id>.nim` with the bot's behavior
5. Add `<id>` to `level.json`'s load order array
6. Touch all modified files, wait 5 seconds, `screenshot` to verify

### Bot script structure

```nim
color = green
speed = 3
lock = true    # prevents player from picking up the bot

# Simple behavior:
turn player
say "Hello!"

# Or a state machine:
loop:
  nil -> idle
  idle -> follow if player.near(8)
  follow -> idle if player.far(15)

-idle:
  forward 2 .. 5
  turn -45.0 .. 45.0

-follow:
  turn player
  forward 3
```

### Signs and dialog

```nim
# Short bubble only:
say "I'm a bot!"

# Bubble + rich markdown sign panel:
say "Hey!", """
  # Hello

  I can help you learn Enu.

  - [Show me something](<nim://some_proc()>)
"""

# Cycle through lines:
say cycle(["Hello!", "Hi again!", "Still here."])
```

For tutorial-style bots: model the behavior after `tutorial-1/bot_aqslupunw4ndq.nim` — use a state machine with named states, `say` for dialog, and transitions triggered by player proximity or game events.
