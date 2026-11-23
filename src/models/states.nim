import std/[tables, strutils, sequtils, sets, sugar]
import pkg/json_serialization
import core, models/[colors]

proc write_value*(w: var JsonWriter, self: set[LocalStateFlags]) =
  write_value(w, self.to_seq)

log_scope:
  topics = "state"
  ctx = Ed.thread_ctx.id

const
  FOCUS_FLAGS* = {
    EDITOR_FOCUSED, CONSOLE_FOCUSED, DOCS_FOCUSED, SETTINGS_FOCUSED,
    VIEWPORT_FOCUSED,
  }
    ## What has keyboard focus. Exactly one is set: the most recently wanted
    ## one whose panel is open, else the viewport.
  PANEL_OF = {
    EDITOR_FOCUSED: EDITOR_VISIBLE,
    CONSOLE_FOCUSED: CONSOLE_VISIBLE,
    DOCS_FOCUSED: DOCS_VISIBLE,
    SETTINGS_FOCUSED: SETTINGS_VISIBLE,
  }
  TARGET_FLAGS = {RETICLE_VISIBLE, BLOCK_TARGET_VISIBLE}
    ## only one is shown at a time

proc focusable(flags: set[LocalStateFlags], focus: LocalStateFlags): bool =
  for (panel_focus, panel) in PANEL_OF:
    if focus == panel_focus:
      return panel in flags
  true

proc resolve_flags*(
    self: GameState, wants: seq[LocalStateFlags]
): set[LocalStateFlags] =
  debug "resolving flags",
    flags = self.local_flags.value, wants = self.wants.value
  for flag in wants:
    if flag in TARGET_FLAGS:
      result = result - TARGET_FLAGS
    if flag notin FOCUS_FLAGS:
      result.incl flag

  # Flags resolve before the worker creates this instance's player.
  let player = self.player
  # CODE_MODE and NONE (no tool) don't target blocks: hide the block target and
  # keep the reticle up, like play mode.
  if ?player and player.tool in {CODE_MODE, NONE}:
    result = result - TARGET_FLAGS
    result.incl(RETICLE_VISIBLE)

  if not TARGET_FLAGS.any_it(it in result):
    result.incl RETICLE_VISIBLE

  if ?player and PLAYING in player.flags:
    result.excl(BLOCK_TARGET_VISIBLE)
    result.excl(EDITOR_VISIBLE)
    result.incl(RETICLE_VISIBLE)

  if COMMAND_MODE in result:
    if TOUCH_CONTROLS notin result:
      result.incl(MOUSE_CAPTURED)
  elif EDITOR_VISIBLE in result or DOCS_VISIBLE in result or
      SETTINGS_VISIBLE in result:
    result.excl(MOUSE_CAPTURED)

  # A captured mouse (or command mode) is aimed at the world; otherwise the
  # most recently focused open panel has the keyboard.
  if MOUSE_CAPTURED in result or COMMAND_MODE in result:
    result.incl VIEWPORT_FOCUSED
  else:
    var focus = VIEWPORT_FOCUSED
    for i in countdown(wants.high, 0):
      if wants[i] in FOCUS_FLAGS and result.focusable(wants[i]):
        focus = wants[i]
        break
    result.incl focus

  # The pointer is over the world: moved there, captured, or a touch screen
  # aimed with the viewport in front.
  if MOUSE_CAPTURED in result or
      (TOUCH_CONTROLS in result and VIEWPORT_FOCUSED in result):
    result.incl POINTER_IN_VIEWPORT

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
    if flag in TARGET_FLAGS:
      for flag in TARGET_FLAGS:
        self.wants -= flag
      if flag notin self.wants:
        self.wants += flag
  self.resolve_flags

proc replace_flag*(self: GameState, flag: LocalStateFlags) =
  self.replace_flags flag

proc push_flags*(self: GameState, flags: varargs[LocalStateFlags]) =
  for flag in flags:
    if flag in FOCUS_FLAGS:
      # the most recent want wins, so move it to the end
      if self.wants.len == 0 or self.wants[^1] != flag:
        self.wants -= flag
        self.wants += flag
    elif flag notin self.local_flags and
        (self.wants.len == 0 or self.wants[^1] != flag):
      self.wants += flag
    if flag == COMMAND_MODE:
      # leaving command mode goes back to the panel that had focus, even if
      # the world was clicked since
      self.wants -= VIEWPORT_FOCUSED
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
  ## The flags popping `flags` would leave, without popping them.
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
  self: Ed[set[LocalStateFlags]], flag: LocalStateFlags
) {.error: "Use `push_flag`, `pop_flag` and `replace_flag`".}

proc `-=`*(
  self: Ed[set[LocalStateFlags]], flag: LocalStateFlags
) {.error: "Use `push_flag`, `pop_flag` and `replace_flag`".}

proc set_flag*(self: Player, flag: PlayerFlags, value: bool) =
  if value:
    self.flags += flag
  else:
    self.flags -= flag

proc toggle_flag*(self: Player, flag: PlayerFlags) =
  self.set_flag flag, flag notin self.flags

const BLOCK_TOOLS* = {BLUE_BLOCK .. BROWN_BLOCK}

type CreateChoice* = enum
  CREATE_AUTO ## the join rules decide whether a block starts a new unit
  CREATE_ON ## turned on by hand: the next block starts a new unit
  CREATE_OFF
    ## turned off by hand: blocks the rules would start a new unit with join
    ## the last edited unit instead

var
  create_choice* {.threadvar.}: CreateChoice
  create_held* {.threadvar.}: bool
    ## Cmd (macOS) / Ctrl (elsewhere) is held: a click starts a new unit.

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
  let self = GameState(
    start_transform: Transform.init(origin = vec3(0, 1, 0)),
    console: ConsoleModel(log: Ed[seq[string]].init(flags = {SYNC_LOCAL})),
  ).init_ed_fields

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
        self.push_flag EDITOR_VISIBLE
      elif added:
        self.pop_flag EDITOR_VISIBLE

    player.flags.changes:
      if change.item == PLAYING:
        self.resolve_flags
        if added:
          create_choice = CREATE_AUTO

    player.tool_value.changes:
      if added and change.item notin BLOCK_TOOLS:
        create_choice = CREATE_AUTO
        self.pop_flag CREATE_MODE
