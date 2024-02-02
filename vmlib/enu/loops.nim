var context: Context

me.advance_state_machine =
  proc(): bool =
    result =
      if not context.is_nil:
        context.advance()
      else:
        true

proc loop_started(ctx: Context, main_loop: bool) =
  if main_loop:
    context = ctx

proc loop_ended(ctx: Context, main_loop: bool) =
  if main_loop:
    context = nil
