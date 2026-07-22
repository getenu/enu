import godotapi/spatial
import core, states, bots, builds, models/[colors, things]

proc init*(
    _: type Sign,
    message: string,
    more = "",
    owner: Thing,
    transform = Transform.init,
    width = 1.0,
    height = 1.0,
    size = 250 / 1200, # text height in blocks; ≈0.208 == the pre-blocks default
    billboard = false,
    text_only = false,
): Sign =
  let sign_id = "sign_" & generate_id()
  sign_id.own:
    var self = Sign(
      id: sign_id,
      message_value: ed(message),
      more_value: ed(more),
      width_value: ed(width),
      height_value: ed(height),
      size_value: ed(size),
      billboard_value: ed(billboard),
      frame_created: state.frame_count,
      start_color: ACTION_COLORS[BLACK],
      start_transform: transform,
      owner_value: ed(owner),
      text_only: text_only,
      parent: owner,
    )
    self.init_thing
    result = self

method main_thread_joined*(self: Sign) =
  proc_call main_thread_joined(Thing(self))

  state.local_flags.watch:
    if PRIMARY_DOWN.added and HOVER in self.local_flags:
      state.open_sign = self

  self.local_flags.watch:
    if HOVER.added:
      self.local_flags += HIGHLIGHT
      state.push_flag RETICLE_VISIBLE
    elif HOVER.removed:
      self.local_flags -= HIGHLIGHT
      state.pop_flag RETICLE_VISIBLE

method destroy*(self: Sign) =
  self.destroy_impl
