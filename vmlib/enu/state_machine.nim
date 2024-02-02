import std/[macros, strformat, strutils, sequtils, tables]
import types, macro_helpers, base_api

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
    done {.inject.} = true
    first_iteration {.inject.} = true
    frame {.inject.} = Frame()

  when not declared(ctx):
    var ctx {.inject.}: Context
  else:
    var ctx {.inject.} = ctx
  if ctx.is_nil:
    ctx = Context()
    main_loop = true

  proc manager(active: bool): bool =
    let active {.inject, used.} = active
    while true:
      body
      return true

  validate_loop()
  frame.manager = manager
  ctx.stack.add frame

  when declared(loop_started):
    loop_started(ctx, main_loop)

  when declared(loop_ended):
    defer:
      loop_ended(ctx, main_loop)

  var looping = ctx.advance(frame)
  if main_loop and not looping:
    # regular while loop.
    while manager(true):
      discard
  else:
    while looping:
      done = false
      try:
        let previous_state = current_state
        var frames = frame_count()
        frame.action()
        if frame_count() - frames <= 1 and previous_state == current_state:
          # we didn't change states and the action didn't do anything. This probably means that
          # we're stuck in an infinite loop, or idling on a finished command like `up home`.
          # Sleep so we don't freeze or burn excessive CPU.
          sleep()
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
      done = true
      looping = ctx.advance(frame)

macro loop*(body: untyped) =
  discard current_loop(Loop())
  result = new_stmt_list()
  let body =
    if body.kind == nnkNilLit:
      new_stmt_list()
    else:
      body
  result.add(get_ast loop_body(body))
  result = new_block_stmt(result)

macro loop*(sig: untyped, body: untyped): untyped =
  var (name, params, vars) = sig.parse_sig

  let proc_body =
    quote:
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
  result =
    quote:
      when compiles(`call`): `call` else: `call_without_ctx`

proc transition(from_state, to_state, body, immediate: NimNode): NimNode =
  var
    to_state_name: string
    to_state = to_state
    includes: seq[string]
    excludes: seq[string]
    body = body

  proc register(node: NimNode): string =
    result = node.str_val
    current_loop().from_states.add (result, node.copy_nim_node)

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

  result =
    quote:
      when not declared(current_state) or not declared(ctx):
        {.error: "`->` or `==>` must be inside a `loop` ".}
      if `immediate` or (active and done):
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
          raise (ref Halt)()

macro `==>`*(from_state: untyped, to_state: untyped, body: untyped = nil) =
  result = transition(from_state, to_state, body, ident"true")

macro `->`*(from_state: untyped, to_state: untyped, body: untyped = nil) =
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
      task1 -> task2:
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
    (nil, big_square) -> square(counter) as little_square:
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
      action_b ==> loop_b:
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
    nil ==> loop_a as initial_loop:
      echo "initial loop "
    inc counter
    if done:
      initial_loop ==> action_a(name):
        counter = 0
    if counter == 3:
      action_a ==> action_b(name):
        counter = 0
      action_b ==> action_c(name) as ac:
        counter = 0
      ac ==> loop_a:
        counter = 0
    if counter == 70:
      loop_a ==> nil:
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
