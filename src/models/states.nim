import std/[tables, strutils, sequtils, sets, sugar]
import pkg/json_serialization
import core, models/[colors]

proc write_value*(w: var JsonWriter, self: set[LocalStateFlags]) =
  write_value(w, self.to_seq)

log_scope:
  topics = "state"
  ctx = Ed.thread_ctx.id

# only one flag from the group is active at a time
const groups =
  @[
    {
      EDITOR_FOCUSED, CONSOLE_FOCUSED, DOCS_FOCUSED, SETTINGS_FOCUSED,
      VIEWPORT_FOCUSED,
    },
    {RETICLE_VISIBLE, BLOCK_TARGET_VISIBLE},
  ]

proc resolve_flags*(
    self: GameState, wants: seq[LocalStateFlags]
): set[LocalStateFlags] =
  debug "resolving flags",
    flags = self.local_flags.value, wants = self.wants.value
  for flag in wants:
    for group in groups:
      if flag in group:
        for f in group:
          result.excl f
    result.incl flag

  # Flags resolve before the worker creates this instance's player.
  let player = self.player
  # CODE_MODE and NONE (no tool) don't target blocks: hide the block target and
  # keep the reticle up, like play mode.
  if ?player and player.tool in {CODE_MODE, NONE}:
    for flag in groups[1]:
      result.excl(flag)
    result.incl(RETICLE_VISIBLE)

  if not groups[1].any_it(it in result):
    result.incl RETICLE_VISIBLE

  if MOUSE_CAPTURED in result:
    result.incl(VIEWPORT_FOCUSED)

  if COMMAND_MODE in result:
    for flag in groups[0]:
      result.excl(flag)
    result.incl(VIEWPORT_FOCUSED)
    if TOUCH_CONTROLS notin result:
      result.incl(MOUSE_CAPTURED)
  else:
    if EDITOR_VISIBLE in result or DOCS_VISIBLE in result or
        SETTINGS_VISIBLE in result:
      result.excl(MOUSE_CAPTURED)

  if ?player and PLAYING in player.flags:
    result.excl(BLOCK_TARGET_VISIBLE)
    result.excl(EDITOR_VISIBLE)
    result.incl(RETICLE_VISIBLE)

  if TOUCH_CONTROLS in result:
    result.excl(BLOCK_TARGET_VISIBLE)

  if MOUSE_CAPTURED notin result:
    result.excl(RETICLE_VISIBLE)

  debug "resolved flags", flags = result

proc resolve_flags*(self: GameState) =
  let result = self.resolve_flags(self.wants.value)
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
    if flag notin self.local_flags and
        (self.wants.len == 0 or self.wants[^1] != flag):
      self.wants += flag
  self.resolve_flags

proc push_flag*(self: GameState, flag: LocalStateFlags) =
  self.push_flags flag

proc pop_flags*(self: GameState, flags: varargs[LocalStateFlags]) =
  for flag in flags:
    self.wants -= flag

  self.resolve_flags

proc try_pop*(
    self: GameState, flags: varargs[LocalStateFlags]
): set[LocalStateFlags] =
  var wants = self.wants.value.filter_it(it notin flags)
  return self.resolve_flags(wants)

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
  self: EdSet[LocalStateFlags], flag: LocalStateFlags
) {.error: "Use `push_flag`, `pop_flag` and `replace_flag`".}

proc `-=`*(
  self: EdSet[LocalStateFlags], flag: LocalStateFlags
) {.error: "Use `push_flag`, `pop_flag` and `replace_flag`".}

proc set_flag*(self: Player, flag: PlayerFlags, value: bool) =
  if value:
    self.flags += flag
  else:
    self.flags -= flag

proc toggle_flag*(self: Player, flag: PlayerFlags) =
  self.set_flag flag, flag notin self.flags

const BLOCK_TOOLS* = {BLUE_BLOCK .. BROWN_BLOCK}

proc selected_color*(self: Player): Color =
  if self.tool in BLOCK_TOOLS:
    self.tool_colors[ord(self.tool) - ord(BLUE_BLOCK)]
  else:
    ACTION_COLORS[Colors(ord self.tool)]

proc select_tool*(self: Player, tool: Tools) =
  ## Make `tool` active, but only when it's available. Selecting an
  ## unavailable tool is a no-op so the player can't pick a hidden tool.
  if tool in self.tools:
    self.tool = tool

proc init_logger*(self: GameState) =
  self.logger = proc(level, msg: string) {.closure.} =
    if level == "err" and state.config.auto_show_console:
      debug "console visible"
      state.push_flag CONSOLE_VISIBLE
    let msg = \"[b]{level.to_upper}[/b] {msg}"
    debug "logging", msg
    state.console.log += msg & "\n"

proc init*(_: type GameState): GameState =
  let flags = {SYNC_LOCAL}
  let self = GameState(
    player_value: EdValue[Player].init(flags = flags),
    local_flags: EdSet[LocalStateFlags].init(flags = flags),
    global_flags: EdSet[GlobalStateFlags].init(id = "state_global_flags"),
    things: EdSeq[Thing].init(
      # OWNS_MEMBERS (ownerless): nothing cascades into root things, but ed
      # indexes the members so partial subscribers get each thing's ownership
      # closure pushed ahead of the collection (husk-free parse).
      id = "root_things",
      flags = DEFAULT_FLAGS + {OWNS_MEMBERS},
    ),
    config_value: EdValue[Config].init(flags = flags, id = "config"),
    gravity: -80.0,
    show_prototypes: true,
    show_tools: true,
    start_transform: Transform.init(origin = vec3(0, 1, 0)),
    console: ConsoleModel(log: EdSeq[string].init(flags = flags)),
    wants: EdSeq[LocalStateFlags].init(flags = flags),
    level_name_value: EdValue[string].init("", id = "level_name"),
    queued_action_value: EdValue[string].init("", flags = flags),
    server_ctx_name_value: EdValue[string].init("", flags = flags),
    status_message_value: EdValue[string].init("", flags = flags),
    voxel_tasks_value: EdValue[int].init(0, flags = flags),
    test_exit_code_value: EdValue[int].init(-1, flags = flags),
    net_bytes_sent_value: EdValue[int64].init(0'i64, flags = flags),
    net_bytes_received_value: EdValue[int64].init(0'i64, flags = flags),
    net_connections_value: EdValue[int].init(0, flags = flags),
    ed_mem_value: EdValue[int].init(0, flags = flags),
  )

  self.init_logger

  result = self
  self.local_flags.changes:
    if EDITOR_VISIBLE.added:
      self.push_flag EDITOR_FOCUSED
    elif EDITOR_VISIBLE.removed:
      self.pop_flag EDITOR_FOCUSED
    elif DOCS_VISIBLE.added:
      self.push_flag DOCS_FOCUSED
    elif DOCS_VISIBLE.removed:
      self.pop_flag DOCS_FOCUSED
    elif SETTINGS_VISIBLE.added:
      self.push_flag SETTINGS_FOCUSED
    elif SETTINGS_VISIBLE.removed:
      self.pop_flag SETTINGS_FOCUSED

  result = self

proc watch_player*(self: GameState) =
  ## The UI flags that follow this instance's player: the editor opens for
  ## whatever it's coding, and play mode changes what the reticle shows.
  let player = self.player
  player.own:
    player.coding_value.changes:
      if added and ?change.item:
        self.push_flags EDITOR_VISIBLE, EDITOR_OPENING
      elif added:
        self.push_flag EDITOR_OPENING
        self.pop_flag EDITOR_VISIBLE

    player.flags.changes:
      if change.item == PLAYING:
        self.resolve_flags

    player.tool_value.changes:
      if added and change.item notin BLOCK_TOOLS:
        self.pop_flag CREATE_MODE

proc set_create_mode*(self: GameState, on: bool) =
  ## Create mode is a modifier on the block tools: it only turns on with one
  ## selected.
  if not on:
    self.pop_flag CREATE_MODE
  elif self.player.tool in BLOCK_TOOLS:
    self.push_flag CREATE_MODE

proc toggle_create_mode*(self: GameState) =
  self.set_create_mode CREATE_MODE notin self.local_flags

proc select_or_modify*(self: GameState, tool: Tools) =
  ## Select `tool`, or toggle its modifier if it's already selected.
  if tool == self.player.tool:
    self.toggle_create_mode
  else:
    self.player.select_tool tool

when is_main_module:
  import pkg/print
  on_unhandled_exception = nil

  import std/[unittest, sequtils]
  type Node = ref object
  var state = GameState.init

  state.push_flag RETICLE_VISIBLE
  check:
    RETICLE_VISIBLE notin state.local_flags
    BLOCK_TARGET_VISIBLE notin state.local_flags
    COMMAND_MODE notin state.local_flags
    MOUSE_CAPTURED notin state.local_flags

  state.push_flag MOUSE_CAPTURED
  check:
    RETICLE_VISIBLE in state.local_flags
    MOUSE_CAPTURED in state.local_flags
    BLOCK_TARGET_VISIBLE notin state.local_flags

  state.replace_flag BLOCK_TARGET_VISIBLE
  check:
    MOUSE_CAPTURED in state.local_flags
    BLOCK_TARGET_VISIBLE in state.local_flags
    RETICLE_VISIBLE notin state.local_flags

  state.pop_flag MOUSE_CAPTURED
  state.push_flag RETICLE_VISIBLE
  check:
    RETICLE_VISIBLE notin state.local_flags
    BLOCK_TARGET_VISIBLE notin state.local_flags
    COMMAND_MODE notin state.local_flags
    MOUSE_CAPTURED notin state.local_flags

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

  state.push_flag COMMAND_MODE
  check:
    RETICLE_VISIBLE in state.local_flags
    COMMAND_MODE in state.local_flags
    MOUSE_CAPTURED in state.local_flags
    BLOCK_TARGET_VISIBLE notin state.local_flags

  state.pop_flag COMMAND_MODE

  state.push_flag MOUSE_CAPTURED
  assert MOUSE_CAPTURED in state.local_flags

  state.push_flags EDITOR_VISIBLE, EDITOR_OPENING
  assert MOUSE_CAPTURED notin state.local_flags

  state.push_flag COMMAND_MODE
  assert MOUSE_CAPTURED in state.local_flags

  state.pop_flag MOUSE_CAPTURED
  assert MOUSE_CAPTURED in state.local_flags

  state.push_flag EDITOR_OPENING
  state.pop_flag EDITOR_VISIBLE
  assert MOUSE_CAPTURED in state.local_flags

  state.pop_flag COMMAND_MODE
  assert MOUSE_CAPTURED notin state.local_flags

  state.pop_flag EDITOR_VISIBLE
  assert MOUSE_CAPTURED notin state.local_flags

  state.push_flag MOUSE_CAPTURED
  assert MOUSE_CAPTURED in state.local_flags

  state.push_flag DOCS_VISIBLE
  assert MOUSE_CAPTURED notin state.local_flags

  state.push_flag COMMAND_MODE
  assert MOUSE_CAPTURED in state.local_flags
