import core

const
  error_code* = some(99)
  # The non-yielding-script watchdog. Fuel is the VM's loop budget: one per
  # backward jump or call, so it's deterministic and costs nothing to check,
  # and compilation doesn't burn it. In a debug build a runaway loop burns it
  # at 0.5-5M/s depending on the body (calls are the slow end), so 5M trips
  # in 1-10s. Loops that call the host burn it far slower (~0.1M/s when each
  # call returns a vector), so host calls also check the wall clock.
  script_fuel* = 5_000_000'i64
  script_time_limit* = 10.seconds
  # Inside the worker's 1/30 s frame budget, so a host-heavy script yields
  # every frame.
  script_park_after* = 20.milliseconds
  # Immediate draw calls between cooperative pauses (see
  # ScriptCtx.unyielded_draws).
  draw_yield_interval* = 256
  advance_step* = 0.5.seconds
