import std/[tables, strutils, sequtils, sets, sugar]
import core, models/[colors]

log_scope:
  topics = "state"
  ctx = Zen.thread_ctx.id

# only one flag from the group is active at a time
const groups =
  @[
    {EditorFocused, ConsoleFocused, DocsFocused},
    {ReticleVisible, BlockTargetVisible},
    {Playing, Flying}
  ]

proc resolve_flags(self: GameState) =
  debug "resolving flags",
    flags = self.local_flags.value, wants = self.wants.value
  var result: set[LocalStateFlags]
  for flag in self.wants:
    for group in groups:
      if flag in group:
        for f in group:
          result.excl f
    result.incl flag

  if self.tool == CodeMode:
    for flag in groups[1]:
      result.excl(flag)
    result.incl(ReticleVisible)

  if not groups[1].any_it(it in result):
    result.incl ReticleVisible

  if CommandMode in result:
    result.incl(MouseCaptured)
    for flag in groups[0]:
      result.excl(flag)
  else:
    if EditorVisible in result or DocsVisible in result:
      result.excl(MouseCaptured)

  if Playing in result:
    result.excl(BlockTargetVisible)
    result.excl(EditorVisible)
    result.incl(ReticleVisible)

  if MouseCaptured notin result:
    result.excl(ReticleVisible)

  debug "resolved flags", flags = result
  self.local_flags.value = result

proc replace_flags*(self: GameState, flags: varargs[LocalStateFlags]) =
  for flag in flags:
    for group in groups:
      if flag in group:
        for flag in group:
          self.wants -= flag
        if flag notin self.wants:
          self.wants += flag
  self.resolve_flags

proc replace_flag*(self: GameState, flag: LocalStateFlags) =
  self.replace_flags flag

proc push_flags*(self: GameState, flags: varargs[LocalStateFlags]) =
  for flag in flags:
    if flag notin self.wants:
      self.wants += flag
  self.resolve_flags

proc push_flag*(self: GameState, flag: LocalStateFlags) =
  self.push_flags flag

proc pop_flags*(self: GameState, flags: varargs[LocalStateFlags]) =
  for flag in flags:
    self.wants -= flag

  self.resolve_flags

proc pop_flag*(self: GameState, flag: LocalStateFlags) =
  self.pop_flags flag

proc set_flag*(self: GameState, flag: LocalStateFlags, value: bool) =
  if value:
    self.push_flag flag
  else:
    self.pop_flag flag

proc toggle_flag*(self: GameState, flag: LocalStateFlags) =
  if flag notin self.local_flags:
    self.push_flag flag
  else:
    self.pop_flag flag

proc `+=`*(
  self: ZenSet[LocalStateFlags], flag: LocalStateFlags
) {.error: "Use `push_flag`, `pop_flag` and `replace_flag`".}

proc `-=`*(
  self: ZenSet[LocalStateFlags], flag: LocalStateFlags
) {.error: "Use `push_flag`, `pop_flag` and `replace_flag`".}

proc selected_color*(self: GameState): Color =
  action_colors[Colors(ord self.tool)]

proc logger*(level, msg: string) =
  if level == "err":
    debug "console visible"
    state.push_flag ConsoleVisible
  let msg = \"[b]{level.to_upper}[/b] {msg}"
  debug "logging", msg
  state.console.log += msg & "\n"

proc debug*(self: GameState, args: varargs[string, `$`]) =
  logger("debug", args.join)

proc info*(self: GameState, args: varargs[string, `$`]) =
  logger("info", args.join)

proc err*(self: GameState, args: varargs[string, `$`]) =
  logger "err", args.join

proc init*(_: type GameState): GameState =
  let flags = {SyncLocal}
  let self =
    GameState(
      player_value: ~(Player, flags),
      local_flags: ~(set[LocalStateFlags], flags),
      global_flags: ~(set[GlobalStateFlags], id = "state_global_flags"),
      units: ~(seq[Unit], id = "root_units"),
      open_unit_value: ~(Unit, flags),
      config_value: ~(Config, flags, id = "config"),
      tool_value: ~(BlueBlock, flags),
      gravity: -80.0,
      console: ConsoleModel(log: ~(seq[string], flags)),
      open_sign_value: ~(Sign, flags),
      wants: ~(seq[LocalStateFlags], flags),
      level_name_value: ~("", id = "level_name"),
      queued_action_value: ~("", flags),
      status_message_value: ~("", flags),
      voxel_tasks_value: ~(0, flags),
    )
  result = self
  self.open_unit_value.changes:
    if added and change.item != nil:
      self.push_flag EditorVisible
    elif added:
      self.pop_flag EditorVisible

  self.local_flags.changes:
    if EditorVisible.added:
      self.push_flag EditorFocused
    elif EditorVisible.removed:
      self.pop_flag EditorFocused
    elif DocsVisible.added:
      self.push_flag DocsFocused
    elif DocsVisible.removed:
      self.pop_flag DocsFocused

  result = self

when is_main_module:
  import pkg/print
  on_unhandled_exception = nil

  import std/[unittest, sequtils]
  type Node = ref object
  var state = GameState.init

  state.push_flag ReticleVisible
  check:
    ReticleVisible notin state.local_flags
    BlockTargetVisible notin state.local_flags
    CommandMode notin state.local_flags
    MouseCaptured notin state.local_flags

  state.push_flag MouseCaptured
  check:
    ReticleVisible in state.local_flags
    MouseCaptured in state.local_flags
    BlockTargetVisible notin state.local_flags

  state.replace_flag BlockTargetVisible
  check:
    MouseCaptured in state.local_flags
    BlockTargetVisible in state.local_flags
    ReticleVisible notin state.local_flags

  state.pop_flag MouseCaptured
  state.push_flag ReticleVisible
  check:
    ReticleVisible notin state.local_flags
    BlockTargetVisible notin state.local_flags
    CommandMode notin state.local_flags
    MouseCaptured notin state.local_flags

  var added {.threadvar.}: set[LocalStateFlags]
  var removed {.threadvar.}: set[LocalStateFlags]

  state.local_flags.track proc(changes: auto) {.gcsafe.} =
    added = {}
    removed = {}
    for change in changes:
      if Added in change.changes:
        added.incl change.item
      if Removed in change.changes:
        removed.incl change.item

  state.push_flag CommandMode
  check:
    ReticleVisible in state.local_flags
    CommandMode in state.local_flags
    MouseCaptured in state.local_flags
    BlockTargetVisible notin state.local_flags

  state.pop_flag CommandMode

  state.push_flag MouseCaptured
  assert MouseCaptured in state.local_flags

  state.open_unit = Unit()
  assert MouseCaptured notin state.local_flags

  state.push_flag CommandMode
  assert MouseCaptured in state.local_flags

  state.pop_flag MouseCaptured
  assert MouseCaptured in state.local_flags

  state.open_unit = nil
  assert MouseCaptured in state.local_flags

  state.pop_flag CommandMode
  assert MouseCaptured notin state.local_flags

  state.pop_flag EditorVisible
  assert MouseCaptured notin state.local_flags

  state.push_flag MouseCaptured
  assert MouseCaptured in state.local_flags

  state.push_flag DocsVisible
  assert MouseCaptured notin state.local_flags

  state.push_flag CommandMode
  assert MouseCaptured in state.local_flags
