include core

type Direction = object
#const skip_3d = false
proc forward(steps = 1.0) =
  discard

proc back(steps = 1.0) =
  discard

proc left(steps = 1.0): Direction {.discardable.} =
  discard

proc right(steps = 1.0): Direction {.discardable.} =
  discard

proc l(steps = 1.0): Direction {.discardable.} =
  discard

proc r(steps = 1.0): Direction {.discardable.} =
  discard

when not declared(skip_3d):
  proc up(steps = 1.0): Direction {.discardable.} =
    discard

  proc u(steps = 1.0): Direction {.discardable.} =
    discard

  proc down(steps = 1.0): Direction {.discardable.} =
    discard

  proc d(steps = 1.0): Direction {.discardable.} =
    discard

proc turn(direction: proc(steps = 1.0): Direction, degrees = 90.0) =
  var axis =
    if direction == r:
      RIGHT
    elif direction == right:
      RIGHT
    elif direction == l:
      LEFT
    elif direction == left:
      LEFT
    else:
      vec3()

  when not declared(skip_3d):
    if axis == vec3():
      axis =
        if direction == u:
          UP
        elif direction == up:
          UP
        elif direction == d:
          DOWN
        elif direction == down:
          DOWN
        else:
          vec3()

  assert axis != vec3(), "Invalid direction"
  echo "turning ", axis

proc t(direction: proc(steps = 1.0): Direction, degrees = 90.0) =
  turn(direction, degrees)

turn left
t l
turn right
t r
t u
