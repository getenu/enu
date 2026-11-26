## Command loops and states: `loop`, and the `->` and `==>` rules that
## switch between behaviors.

import std/[macros, strformat, strutils, sequtils, tables]
import core, macro_helpers

proc current_loop(value: Loop = nil): Loop =
  var loop {.global.}: Loop
  if not value.is_nil:
    loop = value
  result = loop

proc advance*(ctx: Context, frame: Frame = nil): bool =
  ## advance state machine. Returns true if statemachine is still running.
  ## It's ok to run this from within the statemachine, but Halt exceptions
  ## must be allowed to propagate.
  let stack = ctx.stack
  for i, stack_frame in stack:
    let active = i + 1 == stack.len
    try:
      discard stack_frame.manager(active)
    except Halt:
      # shrink the stack to the current position
      ctx.stack = ctx.stack[0 .. i]
      if stack_frame.action == nil and stack_frame == ctx.stack[^1]:
        discard ctx.stack.pop()
      if frame != stack_frame:
        raise (ref Halt)()
      else:
        break
  result = frame.is_nil or frame.action != nil

macro validate_loop() =
  let state_list = @["any", "others"] & to_seq current_loop().states.keys
  for (state, node) in current_loop().from_states:
    if state notin @["nil"] & state_list:
      let states = (@["nil"] & state_list.deduplicate).join(", ")
      let msg = &"undeclared state {state}. valid: {states}"

      error msg, node

template loop_body(body: untyped) =
  var
    main_loop = false
    current_state {.inject, used.} = "nil"
    action_done {.inject.} = true
    first_iteration {.inject.} = true
    frame {.inject.} = Frame()

  when not declared(ctx):
    var ctx {.inject.}: Context
  else:
    var ctx {.inject.} = ctx
  if ctx.is_nil:
    ctx = Context()
    main_loop = true

  let queries = QueryRun()

  proc manager(active: bool): bool =
    # Runs the body once for every combination of query results, with fresh
    # results each time the loop runs.
    let active {.inject, used.} = active
    let outer_run = query_run
    query_run = queries
    defer:
      query_run = outer_run
    var body_running = false
    template finish_pass() =
      # Every combination of query results has had its turn, so the first
      # switch this pass takes effect.
      if frame.switched:
        frame.switched = false
        queries.clear()
        raise (ref Halt)()

    while true:
      if body_running:
        # Only true after a `continue`, which skips the rest of the rules for
        # this combination. If it was the last, the pass is over, and the
        # current state carries on as usual.
        body_running = false
        if not queries.next_combination():
          finish_pass()
          queries.clear()
          return true
      body_running = true
      body
      body_running = false
      if queries.next_combination():
        continue
      finish_pass()
      queries.clear()
      return true

  validate_loop()
  frame.manager = manager
  ctx.stack.add frame

  if main_loop:
    # Let every script in the level run its setup before the rules' first
    # pass: a pass can pause partway (`sees` waits a tick), and a script
    # that loads meanwhile could change what the rules already checked.
    # (Before `loop_started`, so the nap doesn't run the rules itself.)
    sleep 0.0
  when declared(loop_started):
    loop_started(ctx, main_loop)

  when declared(loop_ended):
    defer:
      loop_ended(ctx, main_loop)
  var looping = ctx.advance(frame)
  loop_finished()
  if main_loop and not looping:
    # regular while loop.
    while manager(true):
      loop_finished()
  else:
    while looping:
      action_done = false
      try:
        let previous_state = current_state
        var frames = frame_count()
        frame.action()
        if frame_count() - frames <= 1 and previous_state == current_state:
          # we didn't change states and the action didn't do anything. This probably means that
          # we're stuck in an infinite loop, or idling on a finished command like `up home`.
          # Sleep so we don't freeze or burn excessive CPU.
          loop_finished()
      except Halt:
        if frame in ctx.stack:
          # we're in the stack (which has already been shrunk)
          # so we don't have to bubble the halt
          continue
        else:
          if main_loop:
            break
          else:
            # bubble the halt
            raise (ref Halt)()
      action_done = true
      looping = ctx.advance(frame)

proc is_transition(n: NimNode): bool =
  n.kind == nnkInfix and (n[0].eq_ident("->") or n[0].eq_ident("==>"))

proc is_loop(n: NimNode): bool =
  n.kind in {nnkCall, nnkCommand} and n[0].kind == nnkIdent and n[0].eq_ident("loop")

proc query_key(n: NimNode): string =
  n.line_info

proc rewrite_condition(n: NimNode, parent: var string): NimNode =
  ## Rewrites the queries (`q as name`) in an `if` condition, left to right.
  ## Each is nested in the one before it; `parent` ends as the last one,
  ## which the branch is nested in.
  if n.kind == nnkInfix and n[0].eq_ident("as"):
    let key = n.query_key
    result = new_call(
      ident"query_as",
      rewrite_condition(n[1], parent),
      n[2],
      new_lit(key),
      new_lit(parent),
    )
    parent = key
  elif n.is_transition:
    result = n
  else:
    result = n.copy_nim_node
    for child in n:
      result.add rewrite_condition(child, parent)

proc rewrite_queries(n: NimNode, parent: string): NimNode =
  ## Gives each query in a loop body a key and the query whose branch it's
  ## in, so the loop can go through the combinations the nesting asks for.
  ## Transitions (`a -> b as c` names a state) and nested loops are left
  ## alone.
  if n.is_transition or n.is_loop or
      n.kind in {nnkProcDef, nnkFuncDef, nnkLambda, nnkTemplateDef, nnkMacroDef}:
    return n
  if n.kind in {nnkIfStmt, nnkElifExpr, nnkIfExpr}:
    result = n.copy_nim_node
    for branch in n:
      if branch.kind in {nnkElifBranch, nnkElifExpr}:
        var nested = parent
        let condition = rewrite_condition(branch[0], nested)
        result.add branch.kind.new_tree(condition, rewrite_queries(branch[1], nested))
      else:
        result.add rewrite_queries(branch, parent)
  elif n.kind == nnkInfix and n[0].eq_ident("as"):
    var nested = parent
    result = rewrite_condition(n, nested)
  else:
    result = n.copy_nim_node
    for child in n:
      result.add rewrite_queries(child, parent)

macro loop*(body: untyped) =
  ## A command loop, the heart of a thing's behavior. The body runs
  ## over and over (about twice a second), switching between states
  ## with `->` rules:
  ##
  ##   loop:
  ##     nil -> wander
  ##     if player.near:
  ##       wander -> hide
  ##
  ## A query (`if Player.hit as p:`) runs the body once for each result.
  discard current_loop(Loop())
  result = new_stmt_list()
  let body =
    if body.kind == nnkNilLit:
      new_stmt_list()
    else:
      rewrite_queries(body, "")
  result.add(get_ast loop_body(body))
  result = new_block_stmt(result)

macro loop*(sig: untyped, body: untyped): untyped =
  var (name, params, vars) = sig.parse_sig

  let proc_body = quote:
    const this_state {.inject.} = `name . ast_to_str`
    `vars`
    loop:
      `body`

  result = new_stmt_list()
  params.add new_ident_defs(ident"ctx", ident"Context", new_nil_lit())

  result.add new_proc(name = ident(name), params = params, body = proc_body)

macro smart_call*(call: untyped) =
  var call_without_ctx = call.copy_nim_tree
  call_without_ctx.del call_without_ctx.len - 1
  result = quote:
    when compiles(`call`): `call` else: `call_without_ctx`

proc is_word(n: NimNode, word: string): bool =
  ## `word` as written, even if it was already resolved to something of the
  ## same name (scripts have a `now()`), or to a call of it.
  case n.kind
  of nnkOpenSymChoice, nnkClosedSymChoice:
    n.len > 0 and n[0].eq_ident(word)
  of nnkIdent, nnkSym:
    n.eq_ident(word)
  of nnkCall:
    n.len == 1 and n[0].is_word(word)
  else:
    false

proc transition(from_state, to_state, body, immediate_arg: NimNode): NimNode =
  var
    to_state_name: string
    to_state = to_state
    includes: seq[string]
    excludes: seq[string]
    body = body

  proc register(node: NimNode): string =
    result = node.str_val
    current_loop().from_states.add (result, node.copy_nim_node)

  var immediate = immediate_arg
  # `a -> b now`: right away, without waiting for `a` to finish.
  # (Not `len in 2 .. 3`: in scripts, `..` picks a random number.)
  if to_state.kind == nnkCommand and to_state.len >= 2 and to_state.len <= 3 and
      to_state[1].is_word("now"):
    immediate = ident"true"
    if to_state.len == 3:
      body = to_state[2]
    to_state = to_state[0]
  # `-> done` leaves the machine.
  if to_state.is_word("done"):
    to_state = new_nil_lit()
  if body.kind == nnkNilLit:
    body = new_stmt_list()
  if from_state.kind == nnkTupleConstr:
    for node in from_state:
      if node.kind == nnkIdent:
        includes.add(node.register)
      elif node.kind == nnkPrefix and node[0].str_val == "-":
        excludes.add(register(node[1]))
      elif node.kind == nnkPrefix and node[0].str_val == "+":
        includes.add(register(node[1]))
      elif node.kind == nnkNilLit:
        includes.add("nil")
      else:
        error "Invalid from state", node
  elif from_state.kind == nnkIdent:
    includes.add register(from_state)
  elif from_state.kind == nnkNilLit:
    includes.add("nil")
  else:
    error "Invalid from state", from_state

  if to_state.kind != nnkNilLit:
    let ctx_arg = new_nim_node(nnkExprEqExpr)
    ctx_arg.add(ident"ctx")
    ctx_arg.add(ident"ctx")
    if to_state.kind == nnkInfix and to_state[0] == ident"as" and
        to_state[2].kind == nnkIdent:
      to_state_name = $to_state[2]
      if to_state[1].kind == nnkIdent:
        let search_name = $to_state[1]
        if search_name in current_loop().states and
            not current_loop().states[search_name].is_nil:
          to_state = current_loop().states[search_name]
        else:
          to_state = new_call(to_state[1], ctx_arg)
      elif to_state[1].kind == nnkCall:
        to_state = to_state[1]
        to_state.add(ctx_arg)
      current_loop().states[to_state_name] = copy_nim_tree to_state
    elif to_state.kind == nnkIdent:
      to_state_name = $to_state
      if to_state_name in current_loop().states and
          not current_loop().states[to_state_name].is_nil:
        to_state = current_loop().states[to_state_name]
      else:
        to_state = new_call(to_state, ctx_arg) #
    elif to_state.kind == nnkCall:
      to_state_name = $to_state[0]
      to_state.add(ctx_arg)
    else:
      error "to_state must be identifier or call", to_state
  else:
    to_state_name = "nil"
    to_state = new_stmt_list()

  if to_state_name != "nil" and to_state_name notin current_loop().states:
    current_loop().states[to_state_name] = nil
  # passing these as seqs sometimes crashes
  # the VM when running in nimscript. Join into a string
  let
    includes_str = includes.join(",")
    excludes_str = excludes.join(",")
    # `-> x` (from nil) starts the machine. It isn't a switch that competes
    # with the rest of the pass: the rules below can act on the new state
    # right away, and `x` hasn't run yet, so `x -> y` still waits for it.
    starting = new_lit(includes == @["nil"] and excludes.len == 0)

  result = quote:
    when not declared(current_state) or not declared(ctx):
      {.error: "`->` or `==>` must be inside a `loop` ".}
    if not frame.switched and (`immediate` or (active and action_done)):
      let
        from_includes: seq[string] = `includes_str`.split(",")
        from_excludes: seq[string] = `excludes_str`.split(",")
      if (
        current_state in from_includes or (
          current_state != "nil" and (
            ("others" in from_includes and `to_state_name` != current_state) or
            "any" in from_includes
          )
        )
      ) and current_state notin from_excludes:
        current_state = `to_state_name`
        first_iteration = true
        proc action() =
          if first_iteration:
            `body`
          smart_call(`to_state`)
          first_iteration = false

        if `to_state_name` != "nil":
          frame.action = action
        else:
          frame.action = nil
        # The first switch wins: later ones this pass are ignored, the rest
        # of the pass (every combination of query results) still runs, and
        # the switch takes effect at its end.
        if `starting`:
          action_done = false
        else:
          frame.switched = true

const BLINK = 0.1
  ## Seconds something has to be gone before it counts as gone. Touching
  ## blinks off for a frame or two when a player lands or bounces, which
  ## would otherwise fire `off` and `on` again.

proc edge*(frame: Frame, key: string, value: bool): int =
  ## For `on` and `off`: 1 the pass `value` becomes true, -1 the pass it
  ## becomes false (and has stayed false for a moment), else 0. A machine's
  ## first pass counts as a change.
  if key notin frame.edges:
    frame.edges[key] = value
    return if value: 1 else: -1
  let was = frame.edges[key]
  if value:
    frame.false_since.del key
    frame.edges[key] = true
    return if was: 0 else: 1
  if not was:
    return 0
  let now = now_seconds()
  let since = frame.false_since.get_or_default(key, now)
  frame.false_since[key] = since
  if now - since >= BLINK:
    frame.false_since.del key
    frame.edges[key] = false
    return -1

proc update_crowd[T: Thing](frame: Frame, key: string, found: seq[T], tracks_left: bool) =
  ## Who's still with an `on ... as` query. Someone gone for a moment has
  ## left: they're dropped, and kept for `off` if there is one.
  let now = now_seconds()
  let found = found.map_it(Thing(it))
  var members = frame.crowds.get_or_default(key)
  var missing = frame.missing.get_or_default(key)
  missing.keep_it_if(it[0] notin found)
  for item in members:
    if item notin found and missing.all_it(it[0] != item):
      missing.add (item, now)
  var still: seq[(Thing, float)]
  for (item, since) in missing:
    if now - since >= BLINK:
      members.keep_it_if(it != item)
      if tracks_left:
        frame.left.mget_or_put(key, @[]).add item
    else:
      still.add (item, since)
  frame.crowds[key] = members
  frame.missing[key] = still

proc arrivals*[T: Thing](
    frame: Frame, key: string, found: seq[T], tracks_left: bool
): seq[T] =
  ## For `on ... as`: who's here but hasn't had their turn yet.
  frame.update_crowd(key, found, tracks_left)
  let members = frame.crowds.get_or_default(key)
  for item in found:
    if Thing(item) notin members:
      result.add item

proc arrived*(frame: Frame, key: string, item: Thing) =
  ## `item`'s `on ... as` block ran.
  if item notin frame.crowds.mget_or_put(key, @[]):
    frame.crowds[key].add item

proc departures*[T: Thing](
    frame: Frame, key: string, found: seq[T]
): seq[T] =
  ## For `off ... as`: who's left but hasn't had their turn yet.
  frame.update_crowd(key, found, true)
  for item in frame.left.get_or_default(key):
    result.add T(item)

proc departed*(frame: Frame, key: string, item: Thing) =
  ## `item`'s `off ... as` block ran.
  if key in frame.left:
    frame.left[key].keep_it_if(it != item)

template enu_arrivals*[T](key: string, query: Query[seq[T]], tracks_left: bool): untyped =
  when not declared(frame):
    {.error: "`on` and `off` only work under `rules`, or in a state that switches states".}
  Query.init(frame.arrivals(key, query.result, tracks_left))

template enu_departures*[T](key: string, query: Query[seq[T]]): untyped =
  when not declared(frame):
    {.error: "`on` and `off` only work under `rules`, or in a state that switches states".}
  Query.init(frame.departures(key, query.result))

template enu_arrived*(key: string, item: Thing) =
  frame.arrived(key, item)

template enu_departed*(key: string, item: Thing) =
  frame.departed(key, item)

template enu_edge*(key: string, value: bool): int =
  when not declared(frame):
    {.error: "`on` and `off` only work under `rules`, or in a state that switches states".}
  frame.edge(key, value)

macro `==>`*(from_state: untyped, to_state: untyped, body: untyped = nil) =
  ## Like `->`, but impatient: switches states right away instead of
  ## waiting for the current state to finish what it's doing.
  result = transition(from_state, to_state, body, ident"true")

macro `->`*(from_state: untyped, to_state: untyped, body: untyped = nil) =
  ## A state change rule. `wander -> hide` means "if we're wandering,
  ## start hiding once this bit of wandering is done"; `wander -> hide now`
  ## switches right away. `-> wander` is where the rules start, and
  ## `-> done` leaves them. `any` matches every state, `others` matches
  ## every state except the one you're switching to, and `(a, b) -> c`
  ## matches either. A block after the switch (`a -> b:`) runs once, at
  ## the moment it happens. The first switch in a pass wins; the rest of
  ## the pass still runs.
  result = transition(from_state, to_state, body, ident"false")

when is_main_module:
  proc task1() =
    echo "task1"

  proc task2() =
    echo "task2"

  var count = 0
  loop:
    inc count
    echo "count: " & $count
    nil -> task1
    if count > 5:
      task1 -> task2 do:
        echo "finished in main"
    if count > 10:
      echo "true true"
      task2 -> nil
    else:
      echo "smaller"

  proc forward(length = 1) =
    echo "forward ", length

  proc turn_right() =
    discard

  proc square(length: int) =
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
    if counter > 100:
      (little_square, big_square) -> nil
    (nil, big_square) -> square(counter) as little_square do:
      inc counter
    little_square -> square(2) as big_square

  proc action_a(name: string) =
    echo "action_a ", name

  proc action_b(name: string) =
    echo "action_b ", name

  proc action_c(name: string) =
    echo "action_c ", name

  proc action_d(name: string) =
    echo "action_d ", name

  proc action_e(name: string) =
    echo "action_e ", name

  loop loop_b(counter = 0, name = "loop_b"):
    inc counter
    nil -> action_d(name)
    if counter == 5:
      action_d -> action_e(name)
    if counter == 10:
      action_e -> action_d(name)
    if counter == 15:
      counter = 0

  loop loop_a(counter = 0, name = "loop_a"):
    nil -> action_b(name)
    inc counter
    if counter == 2:
      action_b ==> loop_b do:
        counter = -20
      loop_b ==> action_c(name)
    if counter == 6:
      action_c ==> nil

  counter = 0
  loop:
    echo "looping"
    inc counter
    if counter == 6:
      break

  counter = 0
  var name = "loop_main"
  loop:
    nil ==> loop_a as initial_loop do:
      echo "initial loop "
    inc counter
    if action_done:
      initial_loop ==> action_a(name) do:
        counter = 0
    if counter == 3:
      action_a ==> action_b(name) do:
        counter = 0
      action_b ==> action_c(name) as ac do:
        counter = 0
      ac ==> loop_a do:
        counter = 0
    if counter == 70:
      loop_a ==> nil do:
        echo "loop_main done ", counter

  loop:
    (any, -action_a) -> nil
    action_a -> action_b("goodbye")
    nil -> action_a("hello")

  counter = 0
  loop:
    inc counter
    echo counter
    if counter == 20:
      break
