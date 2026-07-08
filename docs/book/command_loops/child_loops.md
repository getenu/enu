# Child Loops

Sometimes you want to write a command with its own Command Loop. Imagine we have
a thing that performs two complicated commands, `find_treasure` and
`fight_monster`. `find_treasure` might need to `navigate` an area, `locate`
items of interest, `interact` with them,then return to `home_base` to deposit
them. `fight_monster` could require commands like `evade`, `attack`, `hide`, and
`flee`.

Combining all of this in a single command loop would give us a lot of commands,
many of which are mostly unrelated, and managing our switches could get very
complicated. However, making them entirely separate isn't ideal either, as
there's probably some common functionality between them (die if our health gets
too low, respawn if we get stuck). We also need to switch between the two
commands.

A good way to manage this is by making `find_treasure` and `fight_monster` child
loops rather than regular commands. We can treat them like regular commands in
our main `loop`, but when we switch to them they'll be able to perform more
sophisticated logic than a normal command could. In addition, our main loop will
continue to run along side the the child loop, so we can quickly switch out of
the child loop with a big switch arrow `==>` in response to certain conditions,
without either loop needing to worry about higher level concerns.

Our main loop could look something like this:

```nim
loop find_treasure:
  # Our treasure logic goes here. This loop doesn't have
  # an exit condition.
  if treasure_found:
    # We found it. Start looking again. This will switch
    # from any command apart from `look_for_chest`.
    others ==> look_for_chest

loop fight_monster:
  # Fight logic here. This loop should exit when the
  # monster dies.
  if monster.dead:
    any ==> nil

loop:
  # We want our thing to find_treasure indefinately.
  # `find_treasure` doesn't exit (switch to nil).
  nil -> find_treasure
  if monster.near:
    # find_treasure doesn't need to know anything about
    # monsters. We can break out of it with a big switch
    # arrow if we encounter one.
    find_treasure ==> fight_monster

  # fight_monster does have an exit condition (the monster
  # dies), so we can wait for it to finish using the little
  # switch arrow, then go back to finding treasure.
  fight_monster -> find_treasure

  if health == 0:
    # if our health drops to 0, it doesn't matter what else
    # we're doing. Die immediately. Break out of any
    # command (except die) with a big switch arrow.
    (any, -die) ==> die

    # this would also work:
    # others ==> die

  if stuck:
    # respawn if we're stuck, but only from our two child
    # loops. We don't want to respawn if we're already
    # respawning, or we're dead. Implementation of
    # `respawn` not shown.
    (find_treasure, fight_monster) ==> respawn

  # we're done respawning. Treasure time!
  respawn -> find_treasure
```

Child loops can also call other child loops, in which case both the parent and
grandparent loops can use `==>` to break out of the top level loop. There's no
limit to nesting depth.
