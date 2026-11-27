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

var pair: seq[Sign]
var greeted: seq[string]
var waves = 0

-idle_g:
  sleep 0.05

-wave_g:
  inc waves

- greeting:
  -> idle_g
  on Query.init(pair) as s:
    greeted.add s.message
    idle_g -> wave_g now
  wave_g -> done

var held = 0
var turn2 = 0
var seen: seq[string]

-tick2:
  inc turn2
  sleep 0.05

- skipping:
  -> tick2
  if turn2 == 5:
    tick2 -> done
  inc held
  if held < 4:
    continue
  on Query.init(pair) as s:
    seen.add s.message

var block_passes = 0
var mode_after = 0

-moving_block:
  move:
    sleep 0.5

-after_block:
  mode_after = move_mode

- interrupted_block:
  -> moving_block
  inc block_passes
  if block_passes > 3:
    moving_block -> after_block now
  after_block -> done

proc never_called() =
  one -> three # fine, as long as it never runs

proc stray_switch() =
  one -> two

proc stray_on() =
  on touching:
    inc ons

suite "Rules":
  test "the first switch wins, and the pass finishes":
    visits = @[]
    first_wins()
    # `-> one` starts there, and `one -> two now` acts on it the same pass,
    # so `one` never runs; `one -> three now` is ignored.
    check visits == @["two"]
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

  test "everyone arriving together gets a turn, and the first switch wins":
    pair = @[sign_a, sign_b]
    greeting()
    check greeted == @["a", "b"]
    check waves == 1

  test "continue skips the rest of the rules, and the state carries on":
    var cont_ticks = 0
    var cont_rules = 0
    -cont_tick:
      inc cont_ticks
      sleep 0.05
    - continuing:
      -> cont_tick
      if cont_ticks >= 3:
        cont_tick -> done
      continue
      inc cont_rules # never reached
    continuing()
    check cont_ticks >= 3
    check cont_rules == 0

  test "an arrival a pass doesn't reach gets its turn later":
    pair = @[sign_a, sign_b]
    skipping()
    check seen == @["a", "b"]

  test "move: and build: blocks put the mode back":
    build
    move:
      check move_mode == 2
      build:
        check move_mode == 1
      check move_mode == 2
    check move_mode == 1

  test "even when a switch interrupts the block":
    build
    interrupted_block()
    check mode_after == 1

  test "a switch outside rules fails when it's reached, and says why":
    var message = ""
    try:
      stray_switch()
    except ValueError as e:
      message = e.msg
    check "only works under `rules`" in message

  test "so does on outside rules":
    var message = ""
    try:
      stray_on()
    except ValueError as e:
      message = e.msg
    check "`on` only works under `rules`" in message

test_summary()
