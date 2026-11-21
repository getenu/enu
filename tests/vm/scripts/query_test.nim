# Queries in command loops (`if q as name:`): each run of the loop gets fresh
# results and runs the body once for every combination the nesting asks for.
import std/[sequtils, strutils]
import testing
import state_machine
import core
import base_bridge
import types

var test_thing = Thing()
register_active(test_thing)

proc named(names: varargs[string]): Query[seq[Thing]] =
  Query.init(names.to_seq.map_it(Thing(name: it)))

proc just_added(names: varargs[string]): proc(): Query[seq[Thing]] =
  ## A query that has results the first time it's asked, like
  ## `Player.added`.
  let names = names.to_seq
  var asked = false
  result = proc(): Query[seq[Thing]] =
    if asked:
      named()
    else:
      asked = true
      named(names)

suite "Queries":
  test "each result is handled once":
    let added = just_added("a", "b", "c")
    var seen: seq[string]
    var passes = 0
    loop:
      inc passes
      if added() as t:
        seen.add t.name
      if passes >= 8:
        break
    check seen == @["a", "b", "c"]

  test "a nested query goes through its results for each outer result":
    let players = just_added("p1", "p2")
    var pairs: seq[string]
    var passes = 0
    loop:
      inc passes
      if players() as p:
        if named("b1", "b2", "b3") as b:
          pairs.add p.name & "+" & b.name
      if passes >= 12:
        break
    check pairs ==
      @["p1+b1", "p1+b2", "p1+b3", "p2+b1", "p2+b2", "p2+b3"]

  test "queries side by side aren't multiplied together":
    let hits = just_added("h1", "h2")
    let joins = just_added("j1")
    var count = 0
    var seen: seq[string]
    var passes = 0
    loop:
      inc passes
      if hits() as h:
        seen.add h.name
      if joins() as j:
        seen.add j.name
        inc count
      if passes >= 8:
        break
    check count == 1
    check seen == @["h1", "j1", "h2"]

  test "each run of the loop gets fresh results":
    var seen: seq[string]
    var passes = 0
    loop:
      inc passes
      if named("x", "y") as t:
        seen.add t.name
      if passes >= 6:
        break
    check seen == @["x", "y", "x", "y", "x", "y"]

  test "the first transition wins and drops the rest of the results":
    let added = just_added("r1", "r2", "r3")
    var seen: seq[string]
    var passes = 0

    proc greet() =
      discard

    loop:
      inc passes
      if added() as t:
        seen.add t.name
        nil ==> greet
      if passes >= 6:
        # Once a state is running, `break` doesn't end the loop; going back
        # to `nil` does.
        greet ==> nil
    check seen == @["r1"]

test_summary()
