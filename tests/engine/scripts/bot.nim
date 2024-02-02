#proc quit*(exit_code = 0) = discard
include robot

proc script_echo*(msg: string) =
  discard

proc echo(x: varargs[string, `$`]) =
  script_echo x.join

block:
  def task1:
    forward()
    echo "in task1"
  def task2:
    forward()
    echo "in task2"

  var
    count1 = 0
    count2 = 0

  loop:
    inc count1
    echo "count1: " & $count1 & " count2: " & $count2
    nil -> task1
    if count1 > 5:
      task1 -> task2:
        echo "finished in main"
  do:
    inc count2
    echo "count1: " & $count1 & " count2: " & $count2
    if count2 > 10:
      echo "true true"
      task2 -> nil
    else:
      echo "smaller"

  echo "done loop"

  def square(length):
    4.times:
      forward length
      turn_right()

  var counter = 0
  loop:
    inc counter
    echo "loop ", counter
    if counter == 10:
      break

  counter = 0
  loop:
    (nil, big_square) -> square(counter) as little_square
    little_square -> square(2) as big_square
  do:
    inc counter
    if counter > 100:
      (little_square, big_square) -> nil

  def action_a(name: string):
    echo "action_a ", name
    forward()

  def action_b(name: string):
    echo "action_b ", name
    forward()

  def action_c(name: string):
    echo "action_c ", name
    forward()

  def action_d(name: string):
    echo "action_d ", name
    forward()

  def action_e(name: string):
    echo "action_e ", name
    forward()

  def loop_b:
    var
      counter = 0
      name = "loop_b"
    defer:
      echo "loop b done!"
    loop nil:
      inc counter
      nil -> action_d(name)
      if counter == 5:
        action_d -> action_e(name)
      if counter == 10:
        action_e -> action_d(name)
      if counter == 15:
        counter = 0

  def loop_a:
    var
      counter = 0
      name = "loop_a"
    loop nil:
      nil -> action_b(name)
      inc counter
      if counter == 2:
        action_b -> loop_b as loop_b2:
          counter = -20
        loop_b2 -> action_c(name)
      if counter == 6:
        action_c -> nil
    echo name, " done ", counter

  counter = 0
  loop:
    echo "looping"
    inc counter
    if counter == 6:
      break

  counter = 0
  var name = "loop_main"
  loop nil:
    nil -> loop_a as initial_loop:
      echo "initial loop "
    inc counter
    if done:
      initial_loop -> action_a(name):
        counter = 0
    if counter == 3:
      action_a -> action_b(name):
        counter = 0
      action_b -> action_c(name) as ac:
        counter = 0
      ac -> loop_a:
        counter = 0
    if counter == 70:
      loop_a -> nil:
        echo "loop_main done ", counter
