import core

const
  error_code* = some(99)
  # Instruction budgets for the non-yielding-script watchdog (see
  # ScriptCtx.fuel). Deterministic: a legitimate script costs the same
  # instruction count on any machine or build type, while an infinite
  # non-yielding loop exhausts any finite budget. Only VM *execution* burns
  # fuel — compilation runs natively and is exempt, so a cold machine's slow
  # first compile can't trip this (the wall-clock watchdog this replaces
  # wedged the interpreter exactly that way). Measured on skill-test2:
  # heaviest script ≈ 250k, players.nim ≈ 81k; a runaway loop burns ~2M/s in
  # a debug build, so these trip in a couple of seconds. Calibrate against
  # the "script fuel consumed" debug log if worlds grow heavier.
  script_fuel* = 5_000_000'i64
  # Immediate draw calls between cooperative pauses (see
  # ScriptCtx.unyielded_draws).
  draw_yield_interval* = 256
  advance_step* = 0.5.seconds
