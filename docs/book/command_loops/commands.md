# Writing Commands

A command is a piece of code that can be run to control a unit or to get
information about the world. Enu has many built in commands like `forward`,
`back`, `left`, and `right`, and it's easy to add your own.

Commands start on a new line with a `-` and a space, followed by a name. If the
command needs additional details to do its job you can list them in brackets
separated by commas. Commands are blocks, so the first line ends with `:` and
the command body is nested inside.

```nim
- hello(name):
  echo "hello ", name

- goodbye(name = "Vin"):
  echo "goodbye ", name

hello "Claire"
goodbye "Cal"
```

If a command produces a result its type must appear before the `:`. In the
future this will be handled automatically.

```nim
- hello(name) string:
  result = "hello " & $name

echo hello("Scott")
```

<details class="note">
<summary>Under the hood</summary>

Enu runs on the [Nim](https://nim-lang.org) language, and a command is just a
Nim `proc`. Anything you can do with a command you can also do with a normal
proc.

Command parameters (called details here) will default to Nim's `auto` type if
no type is provided. Each parameter is shadowed by a mutable variable inside the
command body.

</details>
