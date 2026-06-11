## MCP server and CLI exposing Enu to agents. It is an `EdClient` (see ed)
## that subscribes to a running Enu, plus a thin layer of tools that run
## queries against agent bots and animate them for framing shots.
##
## `enu mcp` runs the MCP stdio server. `enu <tool> [--param value ...]`
## makes a one-shot CLI call — the fallback when the MCP connection is
## down, or for scripts and humans. No args prints help.
##
## Subagents share the main agent's MCP server, so the protocol carries no
## caller identity. Instead every tool takes an optional `agent_id`: pass a
## short stable id of your choosing (your name works) and you get your own
## bot, with its own color and position. A swarm of subagents each passing
## their own id drives a swarm of distinctly-colored bots.

import std/[os, strutils, tables, math, monotimes, times]
import pkg/ed
import pkg/nimcp except info
import core, models/[bots, units, colors]

const
  MOVE_SPEED = 50.0 ## units / second
  ANGULAR_SPEED = 180.0 ## degrees / second
  TELEPORT_DIST = 500.0 ## skip the glide past this distance

let
  cli_args = command_line_params()
  server_mode = cli_args.len > 0 and cli_args[0] == "mcp"

# Stable per-process id, reused across reconnects so Enu recognizes and
# supersedes a prior session. Bot ids derive from it. CLI invocations get
# fresh ids too: concurrent commands then never supersede each other (or a
# running server) — each gets its own bots, which Enu drops shortly after
# the command's session ends.
let
  ctx_id = "enu_mcp-" & generate_id()
  connect_addr = get_env("ENU_CONNECT_ADDRESS", "127.0.0.1")

proc slug(s: string): string =
  ## Make an agent id safe for use inside a unit id.
  for c in s:
    result.add(if c.is_alpha_numeric or c in {'-', '_'}: c else: '-')
  if result.len > 24:
    result.set_len(24)

proc bot_id(agent_id: string): string =
  result = "mcp_bot-" & ctx_id
  if agent_id != "":
    result &= "-" & agent_id.slug

# Survives reconnects so bots reappear where they were after an Enu
# restart, keeping things predictable for the agents. Keyed by bot id.
var transforms: Table[string, Transform]

# Partial replica: only what we touch syncs from Enu. `blocking` gives
# synchronous semantics: reading or writing anything that hasn't synced
# yet — root_units on first use, a found bot's containers after a
# reconnect — pumps I/O until it fills, so there's no fetch list and no
# hydration ceremony anywhere below.
let client = EdClient(id: ctx_id, address: connect_addr, partial: true,
                      blocking: true)

proc root_units(): EdSeq[Unit] =
  EdSeq[Unit](client.ctx["root_units"])

proc find_unit(id: string): Unit =
  for unit in root_units():
    if unit.id == id:
      return unit

proc bot_for(agent_id = ""): Bot =
  ## Each agent's bot: found by id (a reconnect after an Enu restart) or
  ## created on first use. EPHEMERAL: Enu reaps it when this session ends.
  ## VOXEL_VIEWER: it can photograph parts of the world no player is
  ## keeping loaded. CLI bots are invisible — one-off commands don't need
  ## an avatar flashing in and out for other players (screenshots render
  ## from a dedicated camera, not the bot node).
  root_units().get_or_init(Bot, bot_id(agent_id)):
    let bot = Bot.init(
      id = bot_id(agent_id),
      transform = transforms.get_or_default(
        bot_id(agent_id), Transform.init(vec3(0, 1, 0))
      ),
    )
    bot.global_flags += EPHEMERAL
    bot.global_flags += VOXEL_VIEWER
    if not server_mode:
      bot.global_flags -= VISIBLE
    bot

proc keep_alive() =
  ## Idle work between requests: tick the connection (reconnecting if Enu
  ## restarted) and remember where our bots are.
  client.tick
  if client.connected:
    for unit in root_units():
      if unit.id.starts_with("mcp_bot-" & ctx_id) and ?unit.transform_value:
        transforms[unit.id] = unit.transform

proc glide(unit: Unit, target: Vector3, rotation = 0.0, instant = false) =
  ## Walk smoothly to `target`, turning to `rotation` degrees, syncing each
  ## frame. Teleports past TELEPORT_DIST, or always with `instant` (one-shot
  ## CLI calls just want the end state).
  if instant or unit.transform.origin.distance_to(target) >= TELEPORT_DIST:
    unit.move_to(target, rotation)
  else:
    client.every(init_duration(milliseconds = 33)):
      if unit.step_toward(
        target, rotation, MOVE_SPEED / 30, ANGULAR_SPEED / 30
      ):
        break
  client.tick # flush the final pose

proc ask(
    unit: Unit, q: UnitQuery, timeout = init_duration(seconds = 30)
): UnitQuery =
  ## File the query against `unit` and wait for the answer. Raises
  ## `SessionLost` if the connection goes away mid-wait.
  let query = unit.query(q)
  if client.tick_until(timeout, query.value.state == DONE):
    return query.value
  unit.query = UnitQuery(state: DONE)
  UnitQuery(
    state: DONE, error: "Error: Enu did not respond within " & $timeout
  )

proc answer(q: UnitQuery): string =
  if q.error != "": q.error else: q.result

proc run(q: UnitQuery, agent_id = ""): string =
  ## Run a query against this agent's bot and wait for Enu's answer.
  client.online:
    try:
      answer bot_for(agent_id).ask(q)
    except SessionLost:
      # The reconnect stranded the query before Enu saw it, so one retry
      # on the fresh session is safe. A second loss propagates.
      answer bot_for(agent_id).ask(q)

proc eval_query(code: string, top_level = false, unit_id = ""): UnitQuery =
  UnitQuery(
    kind: EVAL, code: code, top_level: top_level, unit_id: unit_id
  )

let enu_server = mcp_server("enu", "1.0.0"):
  mcp_tool:
    proc screenshot(agent_id: string = ""): string =
      ## Take a screenshot from your bot's perspective.
      ## Returns the file path to the saved PNG image.
      ## - agent_id: optional id giving each (sub)agent its own bot.
      run UnitQuery(kind: SCREENSHOT), agent_id

  mcp_tool:
    proc screenshot_from_player(with_ui: bool = false): string =
      ## Take a screenshot from the player's first-person camera.
      ## Returns the file path to the saved PNG image.
      ## - with_ui: include UI overlay (toolbar, console, etc.) in the
      ##   shot. Default false captures just the rendered world, matching
      ##   what the player sees with the UI hidden.
      run UnitQuery(
        kind: SCREENSHOT,
        screenshot_from_player: not with_ui,
        screenshot_with_ui: with_ui,
      )

  mcp_tool:
    proc get_console(): string =
      ## Get the current Enu console output.
      run UnitQuery(kind: CONSOLE)

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
      run eval_query(code, top_level, unit_id)

  mcp_tool:
    proc get_level_dir(): string =
      ## Get the directory path of the currently loaded level.
      run UnitQuery(kind: LEVEL_DIR)

  mcp_tool:
    proc get_block_log(): string =
      ## Recent blocks the local player placed or erased via the in-game
      ## block tools, oldest first. One entry per line:
      ##   ago=<sec>s color=<c> unit=<id> local=(x,y,z) global=(x,y,z)
      ## Bounded to 200 entries; auto-cleared on save_and_reload. The
      ## human uses this to annotate the world for the agent: "delete
      ## the units I marked red", "add windows where I erased blocks",
      ## etc.
      run eval_query("block_log(active_unit())")

  mcp_tool:
    proc clear_block_log(): string =
      ## Empty the block log so subsequent placements start a fresh
      ## annotation session.

      run eval_query \"""
        clear_block_log(active_unit())
        "cleared"
      """.dedent.strip

  mcp_tool:
    proc units_near(x, y, z: float, radius: float = 30.0): string =
      ## Return a sorted table of units within `radius` (xz-plane distance)
      ## of (x, y, z). One unit per line, formatted "d=DD.D  id  (X, Y, Z)".
      ## Includes spawner-created clones. Useful for chasing "# CLAUDE:"
      ## marker blocks or quickly enumerating what's near a position.
      run eval_query(\"units_near({x}, {y}, {z}, {radius})")

  mcp_tool:
    proc screenshot_top_down(
        x: float, z: float, size: float = 30.0, agent_id: string = ""
    ): string =
      ## Orthographic top-down screenshot centered on (x, z). `size` is the
      ## half-extent of the visible area in voxel units (default 30 → a
      ## 60×60 voxel area is shown). Use for layout planning — true
      ## top-down map view, no perspective distortion.
      ## - x, z: center of the view in world coordinates.
      ## - size: half-width and half-height in voxel units.
      ## - agent_id: optional id giving each (sub)agent its own bot.
      client.online:
        bot_for(agent_id).glide(vec3(x, 1.0, z), instant = not server_mode)
      run UnitQuery(
        kind: SCREENSHOT, screenshot_top_down: true, screenshot_size: size
      ), agent_id

  mcp_tool:
    proc screenshot_at(
        x, y, z: float,
        distance: float = 30.0,
        height: float = 8.0,
        angle: float = 0.0,
        agent_id: string = "",
    ): string =
      ## Take a framed screenshot of a world position. Your bot smoothly
      ## moves to a vantage `distance` units from (x, y, z), raised by
      ## `height`, around the target by `angle` degrees in the horizontal
      ## plane (0 = south of target, 90 = east, 180 = north, 270 = west)
      ## and rotates to look directly at the target including a downward
      ## tilt. Returns the path to the saved PNG.
      ## - x, y, z: target world position to frame.
      ## - distance: how far back from the target to place the bot (default 30).
      ## - height: how high above target.y to raise the bot (default 8).
      ## - angle: viewing direction around the target in degrees (default 0).
      ## - agent_id: optional id giving each (sub)agent its own bot.
      client.online:
        let
          target = vec3(x, y, z)
          bot = bot_for(agent_id)
          pose = frame(target, distance, height, angle)
        bot.glide(pose.pos, pose.yaw_deg, instant = not server_mode)
        bot.look_at(target)
      run UnitQuery(kind: SCREENSHOT), agent_id

  mcp_tool:
    proc move_unit(id: string, x, y, z: float): string =
      ## Move a unit and persist the new spawn position across reload.
      ## Updates both the live transform and `start_position` (which is what
      ## the level saves), so the change survives a restart.
      ## - id: target unit's id.
      ## - x, y, z: new world position.
      run eval_query \"""
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
      run eval_query \"""
        let u = find_by_id("{id}")
        if u.is_nil:
          "Error: unit not found: {id}"
        else:
          u.delete()
          "deleted {id}"
      """.dedent.strip

  mcp_tool:
    proc set_position(
        x, y, z: float,
        rotation: float = 0.0,
        id: string = "",
        agent_id: string = "",
    ): string =
      ## Move a unit to a position at 50 units/sec. Teleports instantly if
      ## distance >= 500.
      ## - x, y, z: target position in world space.
      ## - rotation: Y-axis rotation in degrees.
      ## - id: unit id to move (default: your bot). Use the player's id to
      ##   move the player.
      ## - agent_id: optional id giving each (sub)agent its own bot.
      client.online:
        let unit =
          if id == "":
            Unit(bot_for(agent_id))
          else:
            find_unit(id)
        if unit.is_nil:
          return "Error: Unit not found: " & id
        unit.glide(vec3(x, y, z), rotation, instant = not server_mode)
        ""

proc remove_bots() =
  ## Proactively remove this invocation's bots so back-to-back CLI calls
  ## don't see their predecessor's ghost (Enu reaps them when the dead
  ## session is noticed, but that takes ~10s — long enough to occlude the
  ## next call's screenshot from the same cached transform).
  if client.connected:
    for unit in root_units().value:
      if unit.id.starts_with("mcp_bot-" & ctx_id):
        root_units() -= unit
    client.flush

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
    result = client.tick_until(init_duration(seconds = 3), client.connected)
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
  remove_bots()
  quit exit_code
