# Loops

Command Loops can help manage the complexity of the logic for your units. They
allow you to run complicated lists of commands and switch between them easily
when situations change.

You can create your [own commands](commands.html), or you can call any of the
built-in Enu [commands](../coding/commands.html) like `forward`, `back`, `turn`,
`sleep`, etc.

A Command Loop always has one and only one active command, which it will call
repeatedly until you switch to some other command. The default command is
`nil`. The first thing a loop must do is switch from `nil` to another command,
using the little switch arrow `->`.

```nim
loop:
  nil -> forward
  # I'll go forward forever!
```

The little switch arrow (`->`) will switch from the command on the left to the
command on the right if it's encountered and the left command has just
completed. If the loop goes through and no switches match, the command will be
run again.

We can control which switches get run by putting them in `if` statements.

```nim
loop:
  nil -> forward
  if player.far:
    forward -> back
  if player.near:
    back -> forward
```

In the above example, the loop immediately switches to `forward`, and will go
forward indefinitely until one of the conditions is met and the command is
switched to something else. If the player gets too far away (more than 100m) and
the command is `forward`, the command will be switched to `back`. If the player
is near (5m) and the command is `back`, it will switch to `forward`. However, if
the player is near and the command is `forward`, nothing will change. The
`if player.near` statement will be true, but `back -> forward` is ignored, since
the current command isn't `back`.

If you want your loop to end at some point, you can switch back to `nil`:

```nim
loop:
  # Some commands can take parameters.
  nil -> forward(10)
  forward -> nil
  # I'll run `forward(10)` a single time, then stop and end
  # the loop.
```

Let's look at something more complicated and introduce the big switch arrow
(`==>`) and switch blocks.

```nim
- wander:
  speed = 1
  forward 5..10
  turn -45..45

- charge:
  speed = 5
  turn player
  forward 1

- flee:
  speed = 3
  turn -player
  forward 1

- attack:
  player.bounce 5
  turn 360

var health = 3

loop:
  nil -> wander
  if 1 in 50:
    # When each `wander` command finishes there's a 1 in 50
    # (2%) chance of our unit getting a sudden burst of
    # energy and switching to the `charge` command.
    # Otherwise we just keep wandering.
    wander -> charge

  if health == 0:
    # We died. Exit the loop. We want this to happen
    # immediately, not after the command finishes, so we
    # use the big switch arrow. We use the special `any`
    # command to say that this should happen regardless of
    # the running command.
    any ==> nil

  if player.hit:
    # If the player touches us while we're wandering, we
    # flee. We want it to happen the instant the player
    # touches us, not when our current `wander` is done, so
    # we use the big switch arrow.

    wander ==> flee:
      # This is a switch block. If the command switches
      # here, the switch block will also run once.
      health -= 1

    # if the player touches us while we're charging, we
    # attack immediately.
    charge ==> attack

  if player.far:
    # If the player is far and we're fleeing, go back to
    # wandering
    flee -> wander

  # Switch to wander when our attack is done. We always
  # want this to happen, so it isn't in a conditional. It
  # only does anything if the current command is `attack`,
  # and we only do it when the attack is done becuase we're
  # using the little switch arrow.
  attack -> wander
```

<details class="note">
<summary>Under the hood</summary>

Command Loops are state machines. Enu runs on the [Nim](https://nim-lang.org)
language, and any Nim proc can be a state. If the proc has a return value it
will be discarded.

</details>
