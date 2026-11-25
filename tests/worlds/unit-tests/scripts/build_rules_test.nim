import testing

drawing = false

var visits: seq[string]
var after_switch = 0

-one:
  visits.add "one"

-two:
  visits.add "two"

-three:
  visits.add "three"

- first_wins:
  -> one
  one -> two now
  one -> three now # ignored: the switch above came first
  inc after_switch # the pass still finishes
  two -> done

var touching = false
var steps = 0
var ons = 0
var offs = 0

-tick:
  inc steps

- edges:
  -> tick
  on touching:
    inc ons
  off:
    inc offs
  if steps == 2:
    touching = true
  if steps == 5:
    touching = false
  if steps == 7:
    tick -> done

var go = false
var slow_finished = 0
var fasts = 0

-slow:
  sleep 0.5
  inc slow_finished

-fast:
  inc fasts

- interrupting:
  -> slow
  if go:
    slow -> fast now
  fast -> done

- waiting:
  -> slow
  if go:
    slow -> fast
  fast -> done

- inner:
  -> one
  one -> done

- outer:
  -> inner
  inner -> two
  two -> done

suite "Rules":
  test "the first switch wins, and the pass finishes":
    visits = @[]
    first_wins()
    check visits == @["one", "two"]
    check after_switch >= 2

  test "on and off fire once each, and the first pass counts":
    edges()
    check ons == 1
    check offs == 2

  test "now interrupts; a plain switch waits for the state to finish":
    go = true
    interrupting()
    check slow_finished == 0
    check fasts == 1
    waiting()
    check slow_finished == 1
    check fasts == 2

  test "-> done leaves a machine, and the outer one carries on":
    visits = @[]
    outer()
    check visits == @["one", "two"]

test_summary()
