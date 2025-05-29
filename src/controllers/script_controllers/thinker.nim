import std/[locks]
import core
import models/states
import libs/llama

var
  thinker_lock: locks.Lock
  work_done: locks.Cond
  thinker {.threadvar.}: Thinker
  state {.threadvar.}: GameState

thinker_lock.init_lock
work_done.init_cond

proc thinker_thread(main_thread_state: GameState) {.gcsafe.} =
  thinker_lock.acquire

  let local_ctx = ZenContext.init(
    id = \"local-thinker-{generate_id()}", label = "local-thinker"
  )

  Zen.thread_ctx = local_ctx
  main_thread_state.local_ctx.subscribe(local_ctx)

  state = main_thread_state.clone_local(local_ctx)

  let config =
    main_thread_state.global_ctx[main_thread_state.config_value].value

  var thinker = Thinker(queries: local_ctx[main_thread_state.ai_queries])

  thinker.queries.changes:
    if added:
      var ai_query = change.item.value
      for token in thinker.llm.generate(ai_query.prompt):
        ai_query.response.add token
        thinker.queries[change.item.key] = ai_query
      ai_query.done = true
      thinker.queries[change.item.key] = ai_query

  work_done.signal
  thinker_lock.release

  thinker.llm = LLM.init(config.model_path)

  var running = true
  try:
    while running:
      local_ctx.boop
  except Exception as e:
    error "Unhandled worker thread exception",
      kind = $e.type, msg = e.msg, stacktrace = e.get_stack_trace

    state.push_flag(NeedsRestart)

  while true:
    local_ctx.boop

proc launch_thinker*(state: GameState): system.Thread[GameState] =
  thinker_lock.acquire
  result.create_thread(thinker_thread, state)
  work_done.wait(thinker_lock)
  thinker_lock.release
