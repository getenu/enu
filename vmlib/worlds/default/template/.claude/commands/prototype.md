Create a named build prototype in this Enu level: $ARGUMENTS

A prototype is a reusable build that can be instantiated multiple times with different parameters.

Steps:
1. `get_level_dir` + `screenshot` to orient yourself
2. Pick a name for the prototype type (CamelCase is conventional: `Tower`, `House`, `OakTree`)
3. Create `LEVEL_DIR/scripts/build_anything.nim` and `LEVEL_DIR/data/build_anything/build_anything.json` with any temporary id — adding `name Tower` to the script makes Enu auto-rename the files to `build_tower.{nim,json}` on first load (CamelCase → snake_case, prefixed with `build_`). Conflict with an existing unit raises a script error.
4. Create the instantiating script and touch it too
5. Wait 5 seconds, `screenshot` to verify

Prototype visibility is controlled per-level via `show_prototypes` in
`level.json` (default `true`). When false, every `name`-declared unit
starts with `show = false` (override with `show = true` in the script).

### Prototype script pattern

```nim
name Tower(height = 10, color = brown, sides = 4)
speed = 0

# The proto runs the same body as its instances. Use the level's
# `show_prototypes = false` (see `level.json`) to hide all protos in
# one place, or `show = false` here to hide just this one.
height.times:
  sides.times:
    forward 8
    turn 360 / sides
  up 1
```

### Instantiating

From any other script:
```nim
Tower.new(height = 20, color = red)
Tower.new(height = 10, color = blue, position = vec3(20, 0, -10))
```

Or from `eval` (for testing):
```nim
# This won't work from eval — prototypes must be instantiated from a unit script context
```

### Animated prototype

```nim
name Door(open = false, width = 10, height = 8)
speed = 0

# Draw:
height.times:
  right width
  turn 180
  up 1

# Animate:
move me
speed = 5
loop:
  nil -> sleep as closed
  if open:
    closed -> left(home + width) as opened
  else:
    opened -> right(home) as closed
```

Set `door_instance.open = true` from any other script to trigger the animation.
