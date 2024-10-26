Enu (https://getenu.com) is an open source programming environment that's like a mix of Minecraft and Logo. It is written in the Nim programming languages, and all programs written inside of it are Nim as well. Like logo, the user can programmatically move a turtle, and the turtle draws as it moves, but in Enu it's dropping 1x1x1 cubes rather than drawing a 2d line.

Enu programs have the following directional commands: forward, back, left, right, up, down. Each of these can take an int or float, and move the turtle by the specified amount in the appropriate direction. To clarify, `up` and `down` move the turtle up or down by the specified amount. They have nothing to do with whether the pen is up or down. `drawing = true` or `drawing = false` is the way to achieve this. With `drawing = true`, the command `forward 10` will draw a line of 10 cubes. With `drawing = false` it will move the turtle, but no blocks will be placed.

The `color` variable controls the color of the dropped blocks, and can be assigned one of the following constants: blue, red, green, black, white, brown. `color = brown` for example. You don't need to define these constants. They're already in scope.

You don't need to define the `drawing` or `color` variables. They're already in scope.

It's also possible to use the `turn` command to change the forward direction of the turtle by passing it a direction. For example, `turn left` will turn the cursor 90 degrees to the left. It's also possible to say `turn right, 45` to turn a specific amount.

There's a `times` template that should ALWAYS be preferred over a for loop when looping for a specific number of times. `10.times:` for example, or `10.times(i):` if we want to access the index variable.

The `in` operator can be used between two numbers for randomness. For example, `if 1 in 2:` will run 50% of the time. `if 1 in 100:` will run 1% of the time. The numbers can be floats or ints. This is the preferred way to handle randomness in Enu.

The `cycle` template can be used like `cycle` in rails.

examples:

```nim

# draw a 10 x 10 x 20 tower

color = black

proc draw_box(length: int) =
  4.times:
    forward length
    turn right

20.times:
  draw_box 10
  up 1
  if 1 in 3:
    # change the color
    color = cycle(white, black, red)
```

```nim
# draw a twisty tower

20.times:
  4.times:
    forward 10
    turn 95
  up 1

```

Using this, I would like you to write me a program that produces a heart that's 20m wide.
