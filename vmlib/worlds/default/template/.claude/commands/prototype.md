Create a named build prototype in this Enu level: $ARGUMENTS

A prototype is a reusable build that can be instantiated multiple times with different parameters.

Steps:
1. `get_level_dir` + `screenshot` to orient yourself
2. Pick a name for the prototype type (CamelCase is conventional: `Tower`, `House`, `Tree`)
3. Pick a unique file ID: `build_<name_lowercase>` (e.g., `build_tower`)
4. Create `LEVEL_DIR/data/<id>/<id>.json` with a world origin and `start_color`
5. Write `LEVEL_DIR/scripts/<id>.nim` defining the prototype
6. Touch both files — Enu auto-detects the prototype
7. Create the instantiating script and touch it too
8. Wait 5 seconds, `screenshot` to verify

### Prototype script pattern

```nim
name Tower(height = 10, color = brown, sides = 4)
speed = 0

# Don't draw anything for the prototype definition itself:
if not is_instance:
  show = false
  quit()

# Draw the instance:
color = color
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
if not is_instance: show = false; quit()

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
