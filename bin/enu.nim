## MCP server and CLI exposing Enu to an agent. It is an `EdClient` (see ed)
## that subscribes to a running Enu, plus a thin layer of tools that run
## queries against an agent bot and animate it for framing shots. All the
## connection-keeping and animation lives in `ed` and `src/agent.nim`.
##
## `enu mcp` runs the MCP stdio server. `enu <tool> [--param value ...]`
## makes a one-shot CLI call — the fallback when the MCP connection is
## down, or for scripts and humans. No args prints help.

import std/[os, strutils, monotimes, times]
import pkg/ed
import pkg/nimcp except info
import core, models/[bots, colors], agent

const CLAUDE_ORANGE = col"E8692A"

let
  cli_args = command_line_params()
  server_mode = cli_args.len > 0 and cli_args[0] == "mcp"

# Stable per-process id, reused across reconnects so Enu recognizes and
# supersedes a prior session. The bot id derives from it. CLI invocations
# get fresh ids too: concurrent commands then never supersede each other
# (or a running server) — each gets its own bot, which Enu drops shortly
# after the command's session ends.
let
  ctx_id = "enu_mcp-" & generate_id()
  connect_addr = get_env("ENU_CONNECT_ADDRESS", "127.0.0.1")

proc bot_id(): string =
  "mcp_bot-" & ctx_id

var
  bot: Bot
  # Survives reconnects so the bot reappears where it was after an Enu
  # restart, keeping things predictable for the agent.
  last_bot_transform = Transform.init(vec3(0, 1, 0))

# Partial replica: only `fetch` (and anything fetched later) syncs from Enu.
# root_units is the unit directory — needed to find/supersede the agent bot;
# the bot's own containers are auto-interest (we create them), and a reconnect
# deep-fetches the prior session's bot (see ensure_agent_bot).
let client = EdClient(
  id: ctx_id,
  address: connect_addr,
  chan_size: 100,
  partial: true,
  fetch: @["root_units"],
)

client.on_connect = proc() =
  # CLI bots are invisible: one-off commands don't need an in-world avatar
  # flashing in and out for other players.
  bot = ensure_agent_bot(
    client.ctx,
    bot_id(),
    CLAUDE_ORANGE,
    last_bot_transform,
    visible = server_mode,
  )

proc keep_alive() =
  ## Idle work between requests: tick the connection (reconnecting if Enu
  ## restarted) and remember where the bot is.
  client.tick
  if not bot.is_nil and ?bot.transform_value:
    last_bot_transform = bot.transform

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
  let q = McpQuery(
    kind: kind,
    code: code,
    top_level: top_level,
    unit_id: unit_id,
    screenshot_from_player: screenshot_from_player,
    screenshot_with_ui: screenshot_with_ui,
    screenshot_top_down: screenshot_top_down,
    screenshot_size: screenshot_size,
  )
  client.ensure_connected
  var r = bot.query(client.ctx, q)
  if r.error.len > 0 and not client.connected:
    # The connection dropped (e.g. Enu restarted) and the query never
    # reached Enu, so re-subscribing and retrying once is safe.
    client.connect
    if client.connected:
      r = bot.query(client.ctx, q)
  if r.error != "": r.error else: r.result

let enu_server = mcp_server("enu", "1.0.0"):
  mcp_tool:
    proc screenshot(): string =
      ## Take a screenshot from the MCP bot's perspective.
      ## Returns the file path to the saved PNG image.
      run_tool(MCP_SCREENSHOT)

  mcp_tool:
    proc screenshot_from_player(with_ui: bool = false): string =
      ## Take a screenshot from the player's first-person camera.
      ## Returns the file path to the saved PNG image.
      ## - with_ui: include UI overlay (toolbar, console, etc.) in the
      ##   shot. Default false captures just the rendered world, matching
      ##   what the player sees with the UI hidden.
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

      run_tool MCP_EVAL, \"""
        clear_block_log(active_unit())
        "cleared"
      """.dedent.strip

  mcp_tool:
    proc units_near(x, y, z: float, radius: float = 30.0): string =
      ## Return a sorted table of units within `radius` (xz-plane distance)
      ## of (x, y, z). One unit per line, formatted "d=DD.D  id  (X, Y, Z)".
      ## Includes spawner-created clones. Useful for chasing "# CLAUDE:"
      ## marker blocks or quickly enumerating what's near a position.
      run_tool(MCP_EVAL, \"units_near({x}, {y}, {z}, {radius})")

  mcp_tool:
    proc screenshot_top_down(x: float, z: float, size: float = 30.0): string =
      ## Orthographic top-down screenshot centered on (x, z). `size` is the
      ## half-extent of the visible area in voxel units (default 30 → a
      ## 60×60 voxel area is shown). Use for layout planning — true
      ## top-down map view, no perspective distortion.
      ## - x, z: center of the view in world coordinates.
      ## - size: half-width and half-height in voxel units.
      client.ensure_connected
      bot.glide(client.ctx, vec3(x, 1.0, z), 0.0, instant = not server_mode)
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
      client.ensure_connected
      bot.look_at(
        client.ctx,
        vec3(x, y, z),
        distance,
        height,
        angle,
        instant = not server_mode,
      )
      run_tool(MCP_SCREENSHOT)

  mcp_tool:
    proc move_unit(id: string, x, y, z: float): string =
      ## Move a unit and persist the new spawn position across reload.
      ## Updates both the live transform and `start_position` (which is what
      ## the level saves), so the change survives a restart.
      ## - id: target unit's id.
      ## - x, y, z: new world position.
      run_tool MCP_EVAL, \"""
        let u = find_by_id("{id}")
        if u.is_nil:
          "Error: unit not found: {id}"
        else:
          u.start_position = vec3({x}, {y}, {z})
          u.position = vec3({x}, {y}, {z})
          "moved " & u.id
      """.dedent.strip

  mcp_tool:
    proc delete_unit(id: string): string =
      ## Remove a unit from the level and delete its on-disk script + data
      ## directory. Cannot be undone. Use sparingly; prefer `move_unit` first
      ## when the unit might just be in the wrong place.
      ## - id: target unit's id.
      run_tool MCP_EVAL, \"""
        let u = find_by_id("{id}")
        if u.is_nil:
          "Error: unit not found: {id}"
        else:
          u.delete()
          "deleted {id}"
      """.dedent.strip

  mcp_tool:
    proc set_position(
        x, y, z: float, rotation: float = 0.0, id: string = ""
    ): string =
      ## Move a unit to a position at 50 units/sec. Teleports instantly if
      ## distance >= 500.
      ## - x, y, z: target position in world space.
      ## - rotation: Y-axis rotation in degrees.
      ## - id: unit id to move (default: MCP bot). Use the player's id to
      ##   move the player.
      client.ensure_connected
      let unit =
        if id == "":
          bot
        else:
          client.ctx.find_unit(id)
      if unit.is_nil:
        return "Error: Unit not found: " & id
      unit.glide(client.ctx, vec3(x, y, z), rotation, instant = not server_mode)
      ""

proc remove_bot() =
  ## Proactively remove this invocation's bot so back-to-back CLI calls
  ## don't see their predecessor's ghost (Enu reaps the bot when the dead
  ## session is noticed, but that takes ~10s — long enough to occlude the
  ## next call's screenshot from the same cached transform).
  if not bot.is_nil and client.connected:
    client.ctx.root_units -= bot
    for _ in 0 .. 2:
      client.ctx.tick
      sleep 20

proc wait_for_connection(): bool =
  ## Tick until the subscription handshake lands, or give up.
  let deadline = get_mono_time() + init_duration(seconds = 3)
  while get_mono_time() < deadline:
    if client.connected:
      return true
    client.tick
    sleep 50
  client.connected

if server_mode:
  info "enu mcp starting", pid = get_current_process_id(), connect_addr
  Ed.bootstrap
  client.connect
  info "Ed context initialized. starting stdio server"
  new_stdio_transport().serve(enu_server, idle = keep_alive)
elif cli_args.len == 0 or cli_args[0] in ["help", "--help", "-h"]:
  echo "enu — drive a running Enu from the command line.\n"
  echo enu_server.help_text("enu")
  echo "\nRun as an MCP server with: enu mcp"
else:
  proc connect_to_enu(): bool {.gcsafe.} =
    Ed.bootstrap
    client.connect
    result = wait_for_connection()
    if not result:
      stderr.write_line "Error: can't reach Enu at " & connect_addr &
        " (is Enu running?)"

  let exit_code = enu_server.dispatch_cli(
    cli_args,
    "enu",
    failure = proc(text: string): bool {.gcsafe.} =
      text.starts_with("Error"),
    setup = connect_to_enu,
  )
  remove_bot()
  quit exit_code
