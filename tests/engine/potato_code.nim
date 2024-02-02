name potato(length = 5, width = 2, color = red, label = "hi", friendly = true)

-wander:
  forward 5
  turn right

-run_away(fast = true, msg = "Help!") string:
  -say_hello() string:
    echo "hello"
    "goodbye"
  echo say_hello()
  echo msg
  msg = "something"
  echo msg
  forward 100

block:
  -test_me:
    echo "hi"

  test_me()

speed = 5
me.speed = 10
echo speed
echo me.speed
run_away()
color = red
var c: Colors = color

proc tester(speed = 50) =
  echo speed

tester(6)

echo speed
block:
  var speed = 5
  echo speed
echo speed
tester(speed = 10)
