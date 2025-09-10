var loop_context: Context

me.advance_state_machine = proc(): bool =
  result =
    if not loop_context.is_nil:
      loop_context.advance()
    else:
      true

proc loop_started(ctx: Context, main_loop: bool) =
  if main_loop:
    loop_context = ctx

proc loop_ended(ctx: Context, main_loop: bool) =
  if main_loop:
    loop_context = nil
