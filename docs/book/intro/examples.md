# Examples

Draw a square:

```nim
forward 10
right 10
back 10
left 10
```

or:

```nim
4.times:
  forward 10
  turn right
```

![Square Example](../assets/square_example.png)

Create a twisting tower:

```nim
var
  length = 20
  height = 50

height.times:
  left length / 2
  back length / 2
  4.times:
    forward length
    turn right
  forward length / 2
  right length / 2
  turn 5
  up 1
```

![Tower Example](../assets/tower_example.png)

Draw randomly:

```nim
up 10
forward 10

(50..100).times:
  forward 2..5
  turn -180..180
  up 0..2
```

![Random Example](../assets/random_example.png)

Set the color to blue randomly with a 1 in 50 chance. Otherwise set it to white:

```nim
if 1 in 50:
  color = blue
  
else:
  color = white
```

or as a one-liner:

```nim
color = if 1 in 50: blue else: white
```

![Random Color Example](../assets/random_color_example.png)

Move forward 10 times, cycling through colors:

```nim
10.times:
  color = cycle(red, black, blue)
  forward 1
```

![Color Cycle Example](../assets/cycle_example.png)

Draw a whole shape at once. A hollow box with a hole erased for a door is an
instant house:

```nim
color = white
box 9, 6, 9, fill = false
box 2, 3, 1, at = vec3(4, 0, 0), color = eraser
```

![House Example](../assets/shape_house.png)

See [Drawing Shapes](../coding/shapes.html) for `box`, `ball`, `can`, `wall`,
and `floor`, or follow the [Build a House](tutorial2.html) tutorial to make one
step by step.
