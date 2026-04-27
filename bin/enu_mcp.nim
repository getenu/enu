import std/[os, monotimes, math]
import pkg/ed
import pkg/nimcp except info
import core, models/[bots, colors]

const
  CLAUDE_ORANGE = col"E8692A"
  TOOL_TIMEOUT = 10.seconds

var
  connect_addr = get_env("ENU_CONNECT_ADDRESS", "127.0.0.1")
  bot: Bot
  last_enu_response: MonoTime

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
  let ready_deadline = get_mono_time() + 5.seconds
  while READY notin bot.global_flags and get_mono_time() < ready_deadline:
    Ed.thread_ctx.tick
    sleep 20
  if READY in bot.global_flags:
    last_enu_response = get_mono_time()

proc connect() =
  info "connect: subscribing", connect_addr
  Ed.thread_ctx.subscribe(connect_addr)
  ensure_bot()

const STALE_TIMEOUT = 8.seconds

proc reconnect() =
  info "reconnect: creating fresh context"
  bot = nil
  last_enu_response = MonoTime()
  Ed.thread_ctx = EdContext.init(
    chan_size = 100, buffer = false, id = "enu_mcp-" & generate_id()
  )
  connect()

proc ensure_connected() =
  Ed.thread_ctx.tick
  let subs = Ed.thread_ctx.subscribers.len
  let bot_ok = not bot.is_nil and ?bot.transform_value
  let stale =
    ?last_enu_response and get_mono_time() - last_enu_response > STALE_TIMEOUT
  if subs == 0 or stale:
    reconnect()
  elif not bot_ok:
    ensure_bot()

proc run_tool(kind: McpQueryKind, code = ""): string =
  ensure_connected()
  bot.mcp_query = McpQuery(kind: kind, code: code, state: MCP_PENDING)

  let start = get_mono_time()
  while true:
    Ed.thread_ctx.tick
    let v = bot.mcp_query
    if v.state == MCP_DONE:
      last_enu_response = get_mono_time()
      return if v.error != "": v.error else: v.result
    elif get_mono_time() - start > TOOL_TIMEOUT:
      info "timeout", timeout = TOOL_TIMEOUT, value = v
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
    proc get_console(): string =
      ## Get the current Enu console output.
      run_tool(MCP_GET_CONSOLE)

  mcp_tool:
    proc eval(code: string): string =
      ## Evaluate Nim code in the Enu scripting context.
      ## Returns the value of the expression, or empty string for statements.
      ## Returns an error message prefixed with "Error" if evaluation fails.
      ## - code: Nim code to evaluate in the Enu VM
      run_tool(MCP_EVAL, code)

  mcp_tool:
    proc get_level_dir(): string =
      ## Get the directory path of the currently loaded level.
      run_tool(MCP_GET_LEVEL_DIR)

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

Ed.thread_ctx = EdContext.init(
  chan_size = 100, buffer = false, id = "enu_mcp-" & generate_id()
)

info "Ed context initialized. starting stdio server"
new_stdio_transport().serve(enu_server)
