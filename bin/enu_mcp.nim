import std/[os, monotimes, math]
import pkg/ed
import pkg/nimcp except info
import core, models/[bots, colors]

const
  CLAUDE_ORANGE = col"E8692A"
  TOOL_TIMEOUT = 30.seconds

var
  connect_addr = get_env("ENU_CONNECT_ADDRESS", "127.0.0.1")
  bot: Bot
  last_enu_response: MonoTime
  # Survives reconnects so the new bot lands where the old one was — keeps
  # things predictable for the agent even when Netty kills our context.
  last_bot_transform: Option[Transform]

# Stable across reconnects. Lets the worker recognize a reconnecting client
# (same id → drop the stale subscription on SUBSCRIBE) instead of holding
# two routes to the same process until the netty keepalive timeout fires.
let ctx_id = "enu_mcp-" & generate_id()

proc bot_id(): string =
  "mcp_bot-" & $Ed.thread_ctx.id

proc root_units(): EdSeq[Unit] =
  EdSeq[Unit](Ed.thread_ctx["root_units"])

proc find_unit(id: string): Unit =
  for u in root_units():
    if u.id == id:
      return u

proc unit_rotation(unit: Unit): float =
  if unit of Player: Player(unit).rotation
  else: rad_to_deg(unit.transform.basis.get_euler().y)

proc set_unit_transform(unit: Unit, pos: Vector3, yaw_deg: float) =
  unit.transform = Transform.init(pos, yaw_deg)
  if unit of Player:
    Player(unit).rotation = yaw_deg

proc set_unit_transform_full(
    unit: Unit, pos: Vector3, yaw_rad, pitch_rad: float
) =
  ## Like set_unit_transform but also tilts around the local X axis (pitch),
  ## which set_unit_transform can't do because Player.rotation only tracks yaw.
  ## Used by screenshot_at to aim the camera vertically.
  ##
  ## Build the look-at basis directly from yaw + pitch. The Euler approach
  ## (init_basis(vec3(pitch, yaw, 0))) and basis multiplication both lean on
  ## conventions that aren't obvious from the call sites and give visibly
  ## rolled horizons at off-axis angles. A camera basis is just:
  ##   forward = world unit vector derived from yaw + pitch
  ##   right   = horizontal perpendicular to forward
  ##   up      = right × forward
  ## with no degrees of freedom for roll.
  let
    cy = cos(yaw_rad)
    sy = sin(yaw_rad)
    cp = cos(pitch_rad)
    sp = sin(pitch_rad)
  # yaw_rad = 0 means facing -Z (north) per screenshot_at's atan2(dir.x, -dir.z).
  # Positive pitch tips forward into the ground (pitch_rad sign matches the
  # geometric "look-down" expected by screenshot_at).
  let
    forward = vec3(float32(sy * cp), float32(-sp), float32(-cy * cp))
    right = vec3(float32(cy), 0'f32, float32(sy))
    up = right.cross(forward)
  # init_basis(row0, row1, row2) — rows are the world components of the
  # camera's local axes. Column j = (row0[j], row1[j], row2[j]) is where
  # local axis j ends up in world space:
  #   local +X -> right
  #   local +Y -> up
  #   local +Z -> -forward  (camera back; forward is local -Z)
  var t = Transform()
  t.basis = init_basis(
    vec3(right.x, up.x, -forward.x),
    vec3(right.y, up.y, -forward.y),
    vec3(right.z, up.z, -forward.z),
  )
  t.origin = pos
  unit.transform = t
  if unit of Player:
    Player(unit).rotation = rad_to_deg(yaw_rad)

proc ensure_bot() =
  let units = root_units()
  bot = nil
  for u in units:
    if u.id == bot_id():
      bot = Bot(u)
      return

  info "ensure_bot: creating new bot", id = bot_id()
  bot = Bot.init(id = bot_id())
  bot.color = CLAUDE_ORANGE
  bot.global_flags += EPHEMERAL
  units.add(bot)
  # Restore the previous bot's position so reconnects are invisible to the
  # agent. Falls back to (0, 1, 0) on a fresh start so screenshot_at's
  # transform_value guard doesn't bail out.
  bot.transform =
    if last_bot_transform.is_some:
      last_bot_transform.get
    else:
      Transform.init(vec3(0, 1, 0), 0)
  last_enu_response = get_mono_time()

proc connect() =
  info "connect: subscribing", connect_addr
  Ed.thread_ctx.subscribe(connect_addr)
  ensure_bot()

proc reconnect() =
  info "reconnect: creating fresh context", ctx_id
  bot = nil
  last_enu_response = MonoTime()
  Ed.thread_ctx =
    EdContext.init(chan_size = 100, buffer = false, id = ctx_id)
  connect()

const PING_TIMEOUT = 0.5.seconds

proc ping_succeeded(): bool =
  ## Active heartbeat. Cheap when alive (~10-20ms), bounded when dead.
  ## Definitive: a response means both directions of the conn are live.
  if bot.is_nil or not ?bot.transform_value:
    return false
  bot.mcp_query = McpQuery(kind: MCP_PING, state: MCP_PENDING)
  let start = get_mono_time()
  while get_mono_time() - start < PING_TIMEOUT:
    Ed.thread_ctx.tick
    if bot.mcp_query.state == MCP_DONE:
      return true
    sleep 5
  false

proc ensure_connected() =
  try:
    Ed.thread_ctx.tick
  except CatchableError as e:
    info "tick raised; treating as disconnect", msg = e.msg
    reconnect()
    return
  if not bot.is_nil and ?bot.transform_value:
    last_bot_transform = some(bot.transform)
  if Ed.thread_ctx.subscribers.len == 0 or bot.is_nil:
    reconnect()
    return
  if not ping_succeeded():
    info "ping failed, reconnecting"
    reconnect()

proc run_tool(
    kind: McpQueryKind,
    code = "",
    top_level = false,
    unit_id = "",
    screenshot_from_player = false,
    screenshot_with_ui = false,
    screenshot_top_down = false,
    screenshot_size: float = 0.0,
): string =
  ensure_connected()
  bot.mcp_query = McpQuery(
    kind: kind,
    code: code,
    state: MCP_PENDING,
    top_level: top_level,
    unit_id: unit_id,
    screenshot_from_player: screenshot_from_player,
    screenshot_with_ui: screenshot_with_ui,
    screenshot_top_down: screenshot_top_down,
    screenshot_size: screenshot_size,
  )

  let start = get_mono_time()
  while true:
    Ed.thread_ctx.tick
    let v = bot.mcp_query
    if v.state == MCP_DONE:
      last_enu_response = get_mono_time()
      return if v.error != "": v.error else: v.result
    elif get_mono_time() - start > TOOL_TIMEOUT:
      info "timeout",
        kind = kind,
        query_state = v.state,
        subs = Ed.thread_ctx.subscribers.len
      bot.mcp_query = McpQuery(state: MCP_DONE)
      return "Error: Enu did not respond within " & $TOOL_TIMEOUT
    sleep 10

let enu_server = mcp_server("enu", "1.0.0"):
  mcp_tool:
    proc screenshot(): string =
      ## Take a screenshot from the MCP bot's perspective.
      ## Returns the file path to the saved PNG image.
      run_tool(MCP_SCREENSHOT)

  mcp_tool:
    proc screenshot_from_player(with_ui: bool = false): string =
      ## Take a screenshot from the player's first-person camera.
      ## - with_ui: include UI overlay (toolbar, console, etc.) in the
      ##   shot. Default false captures just the rendered world, matching
      ##   what the player sees with the UI hidden.
      ## Returns the file path to the saved PNG image.
      run_tool(
        MCP_SCREENSHOT,
        screenshot_from_player = not with_ui,
        screenshot_with_ui = with_ui,
      )

  mcp_tool:
    proc get_console(): string =
      ## Get the current Enu console output.
      run_tool(MCP_GET_CONSOLE)

  mcp_tool:
    proc eval(
        code: string, top_level: bool = false, unit_id: string = ""
    ): string =
      ## Evaluate Nim code in the Enu scripting context.
      ## Returns the value of the expression, or empty string for statements.
      ## Returns an error message prefixed with "Error" if evaluation fails.
      ## - code: Nim code to evaluate in the Enu VM
      ## - top_level: if true, run as module-level code (allows `import`,
      ##   top-level `proc`/`type`, etc.) but returns no value. Default false
      ##   runs inside a `(block: ...)` for scoped locals and return value.
      ## - unit_id: evaluate in the named unit's script context (so
      ##   `self`/`active_unit`/locals resolve in that unit's module).
      ##   Default empty = player.
      run_tool(MCP_EVAL, code, top_level, unit_id)

  mcp_tool:
    proc get_level_dir(): string =
      ## Get the directory path of the currently loaded level.
      run_tool(MCP_GET_LEVEL_DIR)

  mcp_tool:
    proc get_block_log(): string =
      ## Recent blocks the local player placed or erased via the in-game
      ## block tools, oldest first. One entry per line:
      ##   ago=<sec>s color=<c> unit=<id> local=(x,y,z) global=(x,y,z)
      ## Bounded to 200 entries; auto-cleared on save_and_reload. The
      ## human uses this to annotate the world for the agent: "delete
      ## the units I marked red", "add windows where I erased blocks",
      ## etc.
      run_tool(MCP_EVAL, "block_log(active_unit())")

  mcp_tool:
    proc clear_block_log(): string =
      ## Empty the block log so subsequent placements start a fresh
      ## annotation session.
      run_tool(MCP_EVAL, "clear_block_log(active_unit())\n\"cleared\"")

  mcp_tool:
    proc units_near(
        x, y, z: float, radius: float = 30.0
    ): string =
      ## Return a sorted table of units within `radius` (xz-plane distance)
      ## of (x, y, z). One unit per line, formatted "d=DD.D  id  (X, Y, Z)".
      ## Includes spawner-created clones. Useful for chasing "# CLAUDE:"
      ## marker blocks or quickly enumerating what's near a position.
      let code =
        "units_near(" & $x & ", " & $y & ", " & $z & ", " & $radius & ")"
      run_tool(MCP_EVAL, code)

  mcp_tool:
    proc screenshot_top_down(
        x: float, z: float, size: float = 30.0
    ): string =
      ## Orthographic top-down screenshot centered on (x, z). `size` is the
      ## half-extent of the visible area in voxel units (default 30 → a
      ## 60×60 voxel area is shown). Use for layout planning — true
      ## top-down map view, no perspective distortion.
      ## - x, z: center of the view in world coordinates.
      ## - size: half-width and half-height in voxel units.
      ensure_connected()
      # Move the bot to (x, ?, z) so the bot_node positions the ortho
      # camera there. Keep height around 0 (ortho cam sits 200 above
      # regardless).
      let target_pos = vec3(x, 1.0, z)
      let start_pos = bot.transform.origin
      let total_dist = start_pos.distance_to(target_pos)
      const speed = 50.0
      const frame_ms = 33
      const frame_sec = frame_ms.float / 1000.0
      let total_time = max(total_dist / speed, frame_sec)
      if total_dist >= 500.0 or total_time < frame_sec:
        set_unit_transform(bot, target_pos, 0.0)
      else:
        var elapsed = 0.0
        while true:
          Ed.thread_ctx.tick
          elapsed += frame_sec
          let progress = float32(min(elapsed / total_time, 1.0))
          if not ?bot.transform_value:
            break
          set_unit_transform(
            bot, start_pos + (target_pos - start_pos) * progress, 0.0
          )
          if progress >= 1.0:
            Ed.thread_ctx.tick
            break
          sleep frame_ms
      last_enu_response = get_mono_time()
      for _ in 0..2:
        Ed.thread_ctx.tick
        sleep 20
      run_tool(
        MCP_SCREENSHOT, screenshot_top_down = true, screenshot_size = size
      )

  mcp_tool:
    proc screenshot_at(
        x, y, z: float,
        distance: float = 30.0,
        height: float = 8.0,
        angle: float = 0.0,
    ): string =
      ## Take a framed screenshot of a world position. The bot smoothly
      ## moves to a vantage `distance` units from (x, y, z), raised by
      ## `height`, around the target by `angle` degrees in the horizontal
      ## plane (0 = south of target, 90 = east, 180 = north, 270 = west)
      ## and rotates to look directly at the target including a downward
      ## tilt. Returns the path to the saved PNG.
      ## - x, y, z: target world position to frame.
      ## - distance: how far back from the target to place the bot (default 30).
      ## - height: how high above target.y to raise the bot (default 8).
      ## - angle: viewing direction around the target in degrees (default 0).
      ensure_connected()
      let target_pos = vec3(x, y, z)
      let angle_rad = deg_to_rad(angle)
      let bot_pos = vec3(
        x + distance * sin(angle_rad), y + height,
        z + distance * cos(angle_rad)
      )
      let dir = target_pos - bot_pos
      let horiz_dist = sqrt(dir.x * dir.x + dir.z * dir.z)
      let yaw_rad = arctan2(float(dir.x), -float(dir.z))
      let pitch_rad = -arctan2(float(dir.y), float(horiz_dist))
      let yaw_deg = rad_to_deg(yaw_rad)

      # Move the bot smoothly to bot_pos with target yaw. Same speed/limits
      # as set_position so the visual feels consistent.
      let start_pos = bot.transform.origin
      let start_rotation = unit_rotation(bot)
      var angle_diff = yaw_deg - start_rotation
      angle_diff -= round(angle_diff / 360.0) * 360.0
      let total_dist = start_pos.distance_to(bot_pos)
      const speed = 50.0
      const angular_speed = 180.0
      const frame_ms = 33
      const frame_sec = frame_ms.float / 1000.0
      let total_time = max(total_dist / speed, abs(angle_diff) / angular_speed)
      if total_dist >= 500.0 or total_time < frame_sec:
        set_unit_transform_full(bot, bot_pos, yaw_rad, pitch_rad)
      else:
        var elapsed = 0.0
        while true:
          Ed.thread_ctx.tick
          elapsed += frame_sec
          let progress = float32(min(elapsed / total_time, 1.0))
          if not ?bot.transform_value:
            break
          set_unit_transform(
            bot, start_pos + (bot_pos - start_pos) * progress,
            start_rotation + angle_diff * float(progress)
          )
          if progress >= 1.0:
            # Land in final pitched orientation for the screenshot.
            set_unit_transform_full(bot, bot_pos, yaw_rad, pitch_rad)
            Ed.thread_ctx.tick
            break
          sleep frame_ms
      last_enu_response = get_mono_time()
      # Give the game thread a few ticks to apply the new transform before
      # capturing the frame.
      for _ in 0..2:
        Ed.thread_ctx.tick
        sleep 20
      run_tool(MCP_SCREENSHOT)

  mcp_tool:
    proc move_unit(id: string, x, y, z: float): string =
      ## Move a unit and persist the new spawn position across reload.
      ## Updates both the live transform and `start_position` (which is what
      ## the level saves), so the change survives a restart.
      ## - id: target unit's id.
      ## - x, y, z: new world position.
      let code =
        "let u = find_by_id(\"" & id & "\")\n" &
        "if u.is_nil:\n  \"Error: unit not found: " & id & "\"\nelse:\n" &
        "  u.start_position = vec3(" & $x & ", " & $y & ", " & $z & ")\n" &
        "  u.position = vec3(" & $x & ", " & $y & ", " & $z & ")\n" &
        "  \"moved \" & u.id"
      run_tool(MCP_EVAL, code)

  mcp_tool:
    proc delete_unit(id: string): string =
      ## Remove a unit from the level and delete its on-disk script + data
      ## directory. Cannot be undone. Use sparingly; prefer `move_unit` first
      ## when the unit might just be in the wrong place.
      ## - id: target unit's id.
      let code =
        "let u = find_by_id(\"" & id & "\")\n" &
        "if u.is_nil:\n  \"Error: unit not found: " & id & "\"\nelse:\n" &
        "  u.delete()\n  \"deleted " & id & "\""
      run_tool(MCP_EVAL, code)

  mcp_tool:
    proc set_position(
        x, y, z: float, rotation: float = 0.0, id: string = ""
    ): string =
      ## Move a unit to a position at 50 units/sec. Teleports instantly if distance >= 500.
      ## x, y, z: target position in world space.
      ## rotation: Y-axis rotation in degrees.
      ## id: unit id to move (default: MCP bot). Use the player's id to move the player.
      ensure_connected()
      let target_pos = vec3(x, y, z)
      let unit = if id == "": bot else: find_unit(id)
      if unit.is_nil:
        return "Error: Unit not found: " & id
      let start_pos = unit.transform.origin
      let start_rotation = unit_rotation(unit)
      var angle_diff = rotation - start_rotation
      angle_diff -= round(angle_diff / 360.0) * 360.0
      let total_dist = start_pos.distance_to(target_pos)
      const speed = 50.0
      const angular_speed = 180.0
      const frame_ms = 33
      const frame_sec = frame_ms.float / 1000.0
      let total_time = max(total_dist / speed, abs(angle_diff) / angular_speed)
      if total_dist >= 500.0 or total_time < frame_sec:
        set_unit_transform(unit, target_pos, rotation)
      else:
        var elapsed = 0.0
        while true:
          Ed.thread_ctx.tick
          elapsed += frame_sec
          let progress = float32(min(elapsed / total_time, 1.0))
          if not ?unit.transform_value:
            break
          set_unit_transform(
            unit, start_pos + (target_pos - start_pos) * progress,
            start_rotation + angle_diff * float(progress)
          )
          if progress >= 1.0:
            Ed.thread_ctx.tick
            break
          sleep frame_ms
      last_enu_response = get_mono_time()
      ""

info "enu_mcp starting", pid = get_current_process_id(), connect_addr

Ed.bootstrap

Ed.thread_ctx =
  EdContext.init(chan_size = 100, buffer = false, id = ctx_id)

info "Ed context initialized. starting stdio server"
new_stdio_transport().serve(enu_server)
