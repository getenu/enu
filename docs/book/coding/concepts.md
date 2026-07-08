# Core Concepts

## Things

Entities/objects in Enu are referred to as things, and have a base type of
`Thing`. Currently there are `Build` things (voxel objects) and `Bot` things (the
robot). There will be more in the future.

`me` is the thing that owns a script, and is equivalent to `self`/`this` in other
environments. `me` was selected because it's easier for a child to type. `me.`
can be auto-inserted when accessing properties of the thing. For example,
`me.speed = 10` would commonly be written as `speed = 10`. There are probably
bugs with this behavior.  Please report them.

## Prototypes

Enu uses a prototype based object system for things. To allow a thing to be a
prototype, you give it a name. Prototype names start with a capital letter:

```nim
name Ghost
```

Then create a new instance in a different script with `.new`:

```nim
var ghost2 = Ghost.new
```

You can also provide parameters, which can be overridden when creating a new
instance:

```nim
name Ghost(color = white, speed = 5, spookiness = 10)
```

These become properties of the thing (ie `me.spookiness = 5`), but can be treated
like variables in the thing's script due to auto `me` insertion
(`spookiness = 200`).

To create a new instance with specific property values:

```nim
var ghost2 = Ghost.new(spookiness = 11)
```

Parameters can have a default value (`spookiness = 10`), which makes them
optional when creating a new instance. If they should be required, or there's no
reasonable default value to use, specify a type (`spookiness: int`) instead, or
omit both the value and the type, which will make the type `auto`.

<details class="note">
<summary>Under the hood</summary>

Enu runs on the [Nim](https://nim-lang.org) language, and prototypes compile
down to Nim procs. Because Nim's `auto` type can be implicit,
`name Ghost(a, b: int)` treats parameters differently than a plain
`proc Ghost(a, b: int)` would: with the proc, `a` and `b` are both `int`,
whereas the `name` version makes `a` `auto` and `b` `int`.

</details>

`speed`, `color`, and `global` can always be passed to a new instance, even if
the prototype name doesn't include them.
