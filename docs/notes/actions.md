# Actions: loops, states and events

An exploration of how a thing's ongoing behavior should be written, prompted
by `loop` not saying what it does, and by pages not fitting it well.
Prototyped on the `actions-exploration` branch.

## Recommendation

Keep Enu's model, states plus rules that are re-checked all the time. Change
its syntax:

1. **`run` instead of `loop:`.** A bare `run` line, after which everything is
   the thing's rules, re-checked over and over. Setup goes above it, behavior
   below, and nothing is indented.
2. **`on` and `off` instead of `==>`.** `on cond:` holds the rules that should
   interrupt whatever the thing is doing. Rules outside an `on` wait for the
   current action to finish, as `->` does today. One arrow, and the timing
   comes from where it's written. `off cond:` is `on` for a condition that's
   false, and a bare `off:` after an `on` is its `else`.
3. **`move` and `build` without `me`.** Plain templates, so no parentheses or
   shift key. Existing `move me` and `build me` lines are rewritten to them,
   so old scripts keep working.

All three are built on the branch, by rewriting scripts into what `loop`
already does. Inky and the button page below ran in Enu in this form.

Things I'd also consider, not built yet:

- **A bare `-> x`** for "from any other state" (today `others -> x`).
- **State names as yes/no questions** (`if not win_game:`), in place of
  exclusion lists like `(others, -win_game)`.
- **No `nil -> first_state` line.** A thing would start in its first state.

What I'd avoid:

- **Scratch-style concurrent event handlers.** They need rules for
  interrupting and resuming, which is where they get hard (see below).
- **A plain `forever` with a mode variable for anything that has to react
  mid-action.** It's fine for things that only need to be in the right place
  (doors, buttons), and for those it may be the simplest option.

## What there is now

- **`-name:`** defines an action: a command, which in a loop is a state.
- **`loop:`** wraps the rules, which are checked again and again: while a
  command runs, and between passes.
- **`a -> b`** switches from `a` to `b` once the current pass of `a` has
  finished. **`a ==> b`** switches right away, interrupting it.
- Special state names:
  - `nil` is before the first state.
  - `any` is any state, and `others` is any state but the target.
  - `(a, b)` lists several states, and `-a` excludes one.
  - `x as y` gives a call a state name.
  - `reset` is built in.
- **Queries:** `if Player.hit as p:` runs the rules once for each result.
- **`do:`** after a transition runs once, at the switch.

Things people trip on, all visible in the shipped scripts:

- **A transition ends the pass.** Code after it doesn't run. In Inky,
  `charge_player = false` comes after `==> charge`, so it only runs on the
  next pass, when the rule no longer matches. It works by accident.
- **The two arrows.** `->` and `==>` differ only in timing, which is hard to
  see.
- **A wall of special names.** `nil`, `any`, `others`, `-x` and `as` each
  have to be learned.
- **`loop:` indents everything,** and doesn't say what it does.

## Inky, four ways

The `-state:` blocks (`explore`, `attack`, `charge`, `hunt`, `win_game`,
`lose_game`) are the same in every version. Only the rules change.

### Today

```nim
loop:
  if not ?player:
    any ==> sleep
    continue
  nil -> sleep
  if not maze.building:
    sleep -> explore
  if charge_player:
    (explore, hunt, attack) ==> charge
    charge_player = false

  if hit(player) and over(player):
    others ==> win_game
  elif hit(player):
    (others, -win_game) ==> lose_game

  if sees(player, 150):
    (hunt, explore) ==> attack
  else:
    attack -> charge
  charge -> hunt

  if player.far(60):
    hunt -> explore
  (win_game, lose_game) -> reset
  reset -> explore
```

### A plain `forever`

The most conventional version I could write. It uses only procs, `if` and
`elif`, and two yes/no variables for what Inky remembers. It's about as long
and needs no special syntax. Tested: it runs and explores.

```nim
var chasing = false # lost sight of the player mid-attack: charge
var hunting = false # charged: keep hunting until the player gets away

forever:
  if not ?player or maze.building:
    sleep 0.5
  elif player.hit:
    if over player:
      win_game()
    else:
      lose_game()
    reset()
    chasing = false
    hunting = false
  elif charge_player:
    charge_player = false
    charge()
    hunting = true
  elif sees(player, 150):
    attack()
    chasing = true
  elif chasing:
    chasing = false
    charge()
    hunting = true
  elif hunting and player.near(60):
    hunt()
  else:
    hunting = false
    explore()
```

The catch is that it can't interrupt. Each check waits for the current pass
to finish, and an explore pass is a climb plus 5–10 blocks at speed 3, a few
seconds. In my test Inky was still exploring more than ten seconds after the
player came into range, while the rules version attacked straight away. (The
maze roof may have blocked its view, so that isn't a clean comparison, but
the structural point stands.) A Logo-style `forward 10` blocks, so reacting
mid-command needs something like `==>`.

The variables are the other cost. `chasing` and `hunting` are the states the
rules version names, kept by hand, and each has to be reset in the right
places. That's where bugs live.

### Event handlers, Scratch style

```nim
when player.hit:          # interrupts whatever Inky is doing
  if over player: win_game() else: lose_game()
  mode = explore

when charge_player:
  charge_player = false
  mode = charge

forever:
  mode()
  ...                     # and the mode changes again, here or in each state
```

This looks simple, but it needs answers to:

- **What happens to the interrupted action?** Is it dropped or resumed? Does
  the `forever` pick up where it was?
- **Running twice.** Can a handler run again while it's still running?
- **Shared state.** Who owns `mode` when two handlers fire together?

Scratch answers these with concurrent scripts and "stop other scripts", which
is its own set of concepts. It also brings back the mode variable. I don't
think it's simpler than rules.

### `run` with `on` and `off` (built)

```nim
run

off ?player:
  any -> sleep
  continue

nil -> sleep
off maze.building:
  sleep -> explore

on charge_player:
  (explore, hunt, attack) -> charge
  charge_player = false
charge -> hunt

on player.hit:
  if over player:
    others -> win_game
  else:
    (others, -win_game) -> lose_game
(win_game, lose_game) -> reset
reset -> explore

on sees(player, 150):
  (hunt, explore) -> attack
off:
  attack -> charge

if player.far(60):
  hunt -> explore
```

- **Same model,** with no `loop:` and no `==>`. Inside `on`/`off` a switch
  happens now; elsewhere it waits for the current pass.
- **Grouping.** Each `on` groups what happens when something is true, and
  `off` says what happens when it stops.
- **Tested in tutorial-3:**
  - with no player, Inky sleeps;
  - with a player it explores;
  - when it sees the player it switches to `attack` (speed 50, glowing) and
    catches them, which sends the player to the lose spot;
  - setting `charge_player` makes it charge, then hunt, then explore once the
    player is far away.
- **One timing change:** `off: attack -> charge` now switches as soon as Inky
  loses sight, where the old `attack -> charge` waited for the current attack
  pass. An attack pass is a 2-block lunge, so it hardly matters.

With the extra simplifications above:

```nim
run

off ?player:
  -> sleep
  continue
off maze.building:
  sleep -> explore

on charge_player:
  charge_player = false
  (explore, hunt, attack) -> charge
charge -> hunt

on player.hit:
  if over player:
    -> win_game
  elif not win_game:
    -> lose_game
(win_game, lose_game) -> reset
reset -> explore

on sees(player, 150):
  (hunt, explore) -> attack
off:
  attack -> charge

if player.far(60):
  hunt -> explore
```

## Other tutorial scripts

**The door (tutorial-3)** shows something useful: many Enu "state machines"
really mean "be where you should be". Today:

```nim
loop:
  nil -> sleep as door_closed
  if open:
    door_closed -> left(home + width) as door_open
  else:
    door_open -> right(home) as door_closed
```

The same door as a plain loop (a sketch, not run):

```nim
forever:
  if open:
    left home + width
  else:
    right home
  sleep 0.2
```

Moving to `home + width` is a move to a spot, so repeating it once the door
is there does nothing. For things like this, a plain loop is simpler than
states, and we should teach it.

**The button (tutorial-3), with `run`** (a sketch, not run):

```nim
name Button(door = Door, pause = 11.0, ghost = inky)
move

run
nil -> up(home + 0.2)
on ?player and player.hit:
  up -> down(home + 0.2) do:
    door.open = true
    ghost.charge_player = true
off:
  sleep -> up(home + 0.2) do:
    door.open = false
down -> sleep(pause)
glow = cycle(0.0, 0.05)
```

**The tutorial-2 bot** (a sketch, not run; comments dropped) is the clearest
case of why interrupting matters: it switches to `chase` the moment the
player is close, in the middle of wandering.

```nim
run
nil -> wander
(go_home, wander_home) -> wander
caught -> go_home

if start_position.far(20):
  wander -> go_home as wander_home

on player.near(10) and start_position.near(30):
  (wander, wander_home) -> chase do:
    say cycle(hellos)

if player.far(20):
  chase -> go_home

if player.near(3):
  chase -> caught
```

## Pages

The button page fits `run` without any special handling. The page is just
something described on every pass. The version I clicked through in Enu also
had a stylesheet, `pane`s and a bot counter; this one is trimmed:

```nim
var count = 0
var show_maker = false

run

board.page:
  h2 "Count: " & $count
  button "Add one":
    on click:
      inc count
  button(if show_maker: "Hide the bot button" else: "Show the bot button"):
    on click:
      show_maker = not show_maker
  if show_maker:
    button "Make a bot":
      on click:
        Walker.new
```

`on click` inside a page and `on` in the rules are the same idea: when this
is true, do this now. The prototype leaves page blocks alone, so the page
builder still handles its own `on click`. A real version could treat a click
as one more condition `on` understands.

## `move` and `build`

They're now templates without arguments, so a script says `move` or `build`.
`move me` is rewritten to `move`, so old scripts keep working. Scripts no
longer see Nim's own `system.move`, which would otherwise make a bare `move`
ambiguous.

Steering another thing (`move enemy`) is gone. Nothing shipped used it except
an hour-of-code helper, which only needed move mode for itself. A thing
controlling another thing that is also running its own script never had good
answers; telling the other thing what to do (`enemy.open = true`, like the
button and door) is clearer.

`run` and the modes are separate questions. `move` or `build` sets what
`forward` does; `run` starts the rules. Inky does `move`, then `run`. Nothing
stops a script from building inside a state, and `build` and `move` can
change modes in the middle.

## Collections and queries

`if Player.hit as p:` hides the collection: the rules run once per player
touching. It keeps per-thing logic flat, and it's the only way to say "for
each" without a `for` loop. With `on`, the natural form is
`on Player.hit as p:`. I'd keep queries, but only where something can happen
to several things at once (players, bots), and use plain values like
`player.hit` everywhere else.

## Open questions

- **`on` reacts while true, not when it changes.** It's re-checked every pass
  while its condition holds, which is what `if` does today and what Inky
  needs. A "fires once" form would be a separate word.
- **`run` collides with the bot command** that sets running speed. It's only
  used inside scripts' own states, not as a bare line, but `sprint` or
  `speed = 5` would avoid the clash.
- **Named loops (`loop wander:`) are sub-machines.** They'd need a form under
  `run` too, perhaps `-wander:` containing its own `run` section.
- **A transition still ends the pass.** Rules after it don't run until next
  time. That might be fine to keep, if the docs say so plainly.
