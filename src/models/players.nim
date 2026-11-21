import std/[math]
import godotapi/spatial
import core, models/[things, states, colors]

proc init*(_: type Player, id = "player-" & Ed.thread_ctx.id): Player =
  id.own:
    let start = Transform.init(origin = vec3(0, 1, 0))
    # The node writes the body's transform and velocity every physics frame;
    # REJECT_STALE keeps a script's move or stop from losing to a frame that
    # was already on its way (getenu/enu#50).
    let body_flags = DEFAULT_FLAGS + {REJECT_STALE}
    let self = Ed.init(
      Player,
      id = id,
      start_transform = start,
      transform = start,
      tool = BLUE_BLOCK,
      tools = {CODE_MODE .. PLACE_BOT},
      tool_colors = DEFAULT_TOOL_COLORS,
      ed_flags = (transform: body_flags, velocity: body_flags),
    )
    self.init_thing
    self.global_flags += GLOBAL
    self.global_flags += EPHEMERAL

    self.own:
      state.local_flags.changes:
        if RESETTING_VM.added:
          self.frame_created = state.frame_count

      self.tools.changes:
        # Lose the active tool when it's removed; stay in NONE until something
        # is explicitly selected (no auto-recovery when tools come back).
        if removed and change.item == self.tool:
          self.tool = NONE

      self.flags.changes:
        # Playing and flying exclude each other, and no flying while it's
        # disabled.
        if PLAYING.added:
          self.flags -= FLYING
        elif FLYING.added:
          self.flags -= (if FLY_DISABLED in self.flags: FLYING else: PLAYING)
        elif FLY_DISABLED.added:
          self.flags -= FLYING

    result = self

method on_begin_turn*(
    self: Player, direction: Vector3, degrees: float, lean: bool, move_mode: int
): Callback =
  let rotation = floor_mod(self.rotation, 360)
  let degrees =
    if direction == LEFT:
      -degrees
    else:
      degrees
  self.rotation_value.touch rotation - degrees
  self.transform = Transform.init(origin = self.transform.origin)

method collect_garbage*(self: Player) =
  discard

proc open_code*(self: Player): string =
  for thing in self.things:
    if thing of Sign:
      let thing = Sign(thing)
      return thing.message

proc `open_code=`*(self: Player, code: string) =
  for thing in self.things:
    if thing of Sign:
      let thing = Sign(thing)
      if code == "":
        thing.global_flags -= VISIBLE
      else:
        thing.message = code
        thing.more = code
        thing.global_flags += VISIBLE
      return

method destroy*(self: Player) =
  if not self.destroyed and self.things.len > 0:
    Sign(self.things[0]).owner = nil
  self.destroy_impl

proc reset_toolbar*(self: Player, show_tools: bool) =
  ## The toolbar a level starts with: every tool, or none when the level's
  ## script adds back what it needs, in the usual colors.
  self.tools.value = if show_tools: {CODE_MODE .. PLACE_BOT} else: {}
  self.tool_colors.value = DEFAULT_TOOL_COLORS

method worker_thread_joined*(self: Player, worker: Worker) =
  # Someone joining mid-level gets the level's toolbar.
  if SERVER in state.local_flags and self != state.player:
    self.reset_toolbar(state.show_tools)
