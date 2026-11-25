# Actions: loops, states and events

An exploration of how a thing's ongoing behavior should be written, prompted
by `loop` not saying what it does, and by pages not fitting it well.
Prototyped on the `actions-exploration` branch.

## Settled (built)

Enu keeps its model, states plus rules that are re-checked all the time, with
new syntax:

- **`run`.** A bare `run` line replaces `loop:`. Everything after it is the
  thing's rules, re-checked over and over. Setup goes above, behavior below,
  and nothing is indented.
- **`-> x` starts in `x`** (today's `nil -> x`). **`-> done` leaves** the
  machine (today's `-> nil`).
- **`a -> b` waits** for `a` to finish what it's doing. **`a -> b now`**
  switches right away (today's `==>`). A block after the switch, `a -> b:`,
  runs once as it happens.
- **`if cond:` applies while `cond` is true**, checked every pass.
  **`on cond:` runs once, the moment `cond` becomes true**, and **`off
  cond:` the moment it becomes false**. A bare `off:` after an `on` is the
  `off` for the same condition. A machine's first pass counts as a change,
  so a script that starts with the condition already true still reacts.
- **The first switch in a pass wins, and the pass finishes.** Later switches
  that pass are ignored, so order is priority, but the rest of the rules
  still run. The switch takes effect at the end of the pass.
- **A state whose block has rules is a machine of its own** (in place of
  `loop name:`). It runs while its state is current, and the outer rules can
  interrupt it.
- **`move` and `build` without `me`.** `move me` and `build me` are rewritten
  to them, so old scripts keep working.
- **The old `run` and `walk` commands are gone.** Setting `speed` does the
  same.

`==>`, `nil` and `do:` still work, so existing scripts run unchanged. All
existing tests pass. New ones (`tests/worlds/unit-tests/scripts/
build_rules_test.nim`) cover:
- the first switch winning while the pass finishes;
- `on`/`off` firing once each, with the first pass counting;
- `now` interrupting, and a plain switch waiting;
- `-> done` leaving a machine.

Inky, in this form (ran in tutorial-3: explore, attack, charge, hunt, and a
catch ending the game):

```nim
run

-> sleep
if not ?player:
  any -> sleep now
  continue # the rules below need a player

if not maze.building:
  sleep -> explore

if charge_player:
  charge_player = false
  (explore, hunt, attack) -> charge now
charge -> hunt

on player.hit:
  if over player:
    others -> win_game now
  else:
    (others, -win_game) -> lose_game now
(win_game, lose_game) -> reset
reset -> explore

if sees(player, 150):
  (hunt, explore) -> attack now
else:
  attack -> charge

if player.far(60):
  hunt -> explore
```

`continue` is still useful when the rest of the rules can't run. Here they
need a player, and without the `continue` `player.far(60)` fails when there
isn't one.

Not built yet:

- **State names as yes/no questions** (`if not win_game:`), in place of
  exclusion lists like `(others, -win_game)`.
- **Switching the shipped scripts, docs and skills** to the new syntax, and
  `do:` to the colon form.

What I'd avoid:

- **Scratch-style concurrent event handlers.** They need rules for
  interrupting and resuming, which is where they get hard (see below).
- **A plain `forever` with a mode variable for anything that has to react
  mid-action.** It's fine for things that only need to be in the right place
  (doors, buttons), and for those it may be the simplest option.

The rest of this note is how we got here.

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

### `run` with `on` and `off` (first draft)

This first draft had `on` switch right away; the settled design above uses
`now` for that, and `on` means "once".

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

With a bare `-> x` for the start, state names as questions, and the first
switch winning while the pass finishes (so no `continue`, and
`charge_player = false` can go anywhere):

```nim
run

-> sleep
off ?player:
  any -> sleep
off maze.building:
  sleep -> explore

on charge_player:
  charge_player = false
  (explore, hunt, attack) -> charge
charge -> hunt

on player.hit:
  if over player:
    others -> win_game
  elif not win_game:
    others -> lose_game
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

## States that are machines (built)

A `-name:` block whose body has rules (arrows, `on`, `off`) is a machine of
its own: it runs while the state it's in is current, and the outer rules keep
being checked, so they can interrupt it. A block without rules stays an
action. Nothing new to learn: if it switches states, it's a machine.

```nim
-wait:
  sleep 0.2

-hunt:
  forward 2
  turn -90 .. 90

-dig:
  inc digs
  sleep 0.3

- explore:
  -> hunt
  on near_treasure:
    hunt -> dig
  dig -> hunt

run

-> wait
on started:
  wait -> explore
```

A bare `-> x` is where a machine starts (today's `nil -> x`). Tested with a
bot: it waited, started exploring when `started` turned on, dug repeatedly
(with a step of hunting between digs) while `near_treasure` was on, and went
back to hunting when it turned off.

The old `run` and `walk` commands are gone. Setting `speed` does the same,
and picks the walk or run animation.

## `on`: while true, or the moment it becomes true?

Built as "while true". Cases it handles that "the moment it becomes true"
doesn't:

1. **The condition turns true in the wrong state.** `on sees(player, 150):
   (hunt, explore) -> attack`. If Inky is mid-`charge` when the player comes
   into view, the rule doesn't apply yet. While true, it applies the moment
   the charge ends; on change, the moment has passed, and Inky hunts a player
   it can see. Any rule with a list of states it applies from has this
   problem.
2. **It was already true.** The level loads, or a script reloads (which Enu
   does all the time while you edit), with the player already on the button,
   already near the guard, or the door's `open` already set. On change,
   nothing happens until it goes false and true again.
3. **Coming back after an interruption.** A guard chases while the player is
   near, gets knocked into `flinch` by a hit, and goes `flinch -> idle`. While
   true, it chases again straight away; on change, it idles beside a player
   who never left.
4. **Keep doing it while it lasts.** The digger digs while it's near the
   treasure, as many times as it takes.

Where "the moment it becomes true" is needed: counting and one-off effects
without a change of state. `on player.hit: score += 1` adds a point every
pass while touching, and `say "Ouch!"` repeats. Most of these become fine
when the effect sits behind a switch, in the state it switches to or a `do:`
block, because the switch only happens once (the coin vanishes, the bot goes
to `flinch`). A counter that keeps counting while you stand on it does need
an edge, so I'd add a second, explicit form later if scripts need one, and
keep `on` as "while true". Every rule in the shipped scripts is guarded by
the state it switches from, and works the same either way.

## Should a switch end the pass?

For ending it:

- **Order is priority.** Rules are read top to bottom and the first switch
  wins. In Inky the hit rules come before the sight rules, so a catch beats
  an attack. If the pass carried on, a later `any`/`others` rule could switch
  again in the same pass, the last switch would win, and the priority you see
  on the page would be backwards.
- **One `do:` per pass.** Two switches in a pass would run two `do:` blocks:
  a door's open and close in the same instant, or a bot saying two things at
  once.
- **Queries.** A switch clears the run's query results (`as`), so the next
  pass starts fresh, not halfway through a list of players.

Against:

- **Code after a switch silently doesn't run.** Inky's
  `charge_player = false` sits after its switch and only works because the
  next pass skips the rule. The button's `glow = cycle(...)` at the end of its
  rules skips a beat whenever it switches. A page described below a switch
  updates one pass late.
- **Order of bookkeeping matters.** `on coin.hit: -> celebrate` followed by
  `score += 1` loses the point.

A middle way keeps the good part: **the first switch wins, but the pass
finishes.** Later switches in the same pass are ignored, so order is still
priority and there's still one `do:`, and everything else still runs. Inky's
`continue` after `any -> sleep` becomes unnecessary too. The switch takes
effect at the end of the pass, which is immediate in practice, since rules
don't run commands. Not built; it means deferring the switch in
`state_machine.nim` instead of raising `Halt`.

## Open questions

- **`on Player.hit as p:`**, once per player as each one starts touching,
  isn't built. `on` with `as` is an error for now; `if ... as` still works.
