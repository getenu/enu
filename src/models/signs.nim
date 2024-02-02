import godotapi/spatial
import core, states, bots, builds, models/[colors, units]

proc init*(
    _: type Sign,
    message: string,
    more = "",
    owner: Unit,
    transform = Transform.init,
    width = 1.0,
    height = 1.0,
    size = 32,
    billboard = false,
    text_only = false,
): Sign =
  var self =
    Sign(
      id: "sign_" & generate_id(),
      message_value: ~message,
      more_value: ~more,
      width_value: ~width,
      height_value: ~height,
      size_value: ~size,
      billboard_value: ~billboard,
      frame_created: state.frame_count,
      start_color: action_colors[black],
      start_transform: transform,
      owner_value: ~owner,
      text_only: text_only,
      parent: owner,
    )
  self.init_unit
  result = self

method main_thread_joined*(self: Sign) =
  proc_call main_thread_joined(Unit(self))

  state.local_flags.watch:
    if PrimaryDown.added and Hover in self.local_flags:
      state.open_sign = self

  self.local_flags.watch:
    if Hover.added:
      self.local_flags += Highlight
      state.push_flag ReticleVisible
    elif Hover.removed:
      self.local_flags -= Highlight
      state.pop_flag ReticleVisible

method destroy*(self: Sign) =
  self.destroy_impl
