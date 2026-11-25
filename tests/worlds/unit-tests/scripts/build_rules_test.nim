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
  sleep 0.2 # longer than a blink, so a change counts

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

var crowd: seq[Sign]
var arrivals: seq[string]
var departures: seq[string]
var turn = 0
let sign_a = say("a")
let sign_b = say("b")

-step:
  inc turn
  case turn
  of 1: crowd = @[sign_a]
  of 2: crowd = @[sign_a, sign_b]
  of 3: crowd = @[sign_b]
  of 4: crowd = @[]
  else: discard
  sleep 0.2 # longer than a blink, so a departure counts

- watching:
  -> step
  on Query.init(crowd) as s:
    arrivals.add s.message
  off:
    departures.add s.message
  if turn == 5:
    step -> done

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

  test "on ... as runs once for each arrival, and off for each departure":
    watching()
    check arrivals == @["a", "b"]
    check departures == @["a", "b"]

  test "a blink isn't a departure":
    var blinker: seq[Sign] = @[sign_a]
    var blink_arrivals = 0
    var blink_departures = 0
    var blink_turn = 0
    -blink_step:
      inc blink_turn
      blinker = if blink_turn == 2: @[] else: @[sign_a]
      sleep 0.03
    - blinking:
      -> blink_step
      on Query.init(blinker) as s:
        inc blink_arrivals
      off:
        inc blink_departures
      if blink_turn == 6:
        blink_step -> done
    blinking()
    check blink_arrivals == 1
    check blink_departures == 0

test_summary()
