import std/[os, strutils, math]
import pkg/nimcp
import client
import core, models/[bots, units, colors]

const
  MOVE_SPEED = 50.0
  ANGULAR_SPEED = 180.0
  TELEPORT_DIST = 500.0

let
  cli_args = command_line_params()
  server_mode = cli_args.len > 0 and cli_args[0] == "mcp"
  ctx_id = "enu_mcp-" & generate_id()

proc slug(s: string): string =
  for c in s:
    result.add(if c.is_alpha_numeric or c in {'-', '_'}: c else: '-')
  if result.len > 24:
    result.set_len(24)

proc bot_id(agent_id: string): string =
  result = "mcp_bot-" & ctx_id
  if agent_id != "":
    result &= "-" & agent_id.slug

proc last_transform(id: string): Transform =
  result = Transform.init(vec3(0, 0, 0))
  if not Enu.client.prev.is_nil and "root_units" in Enu.client.prev:
    for unit in EdSeq[Unit](Enu.client.prev["root_units"]):
      if unit.id == id and ?unit.transform_value:
        return unit.transform

proc bot_for(agent_id = ""): Bot =
  Enu.units.get_or_init(Bot, bot_id(agent_id)):
    let pos = last_transform(bot_id(agent_id)).origin
    let bot = Bot.init(pos.x, pos.y, pos.z, id = bot_id(agent_id))
    bot.color = col(bot.id.hash)
    bot.global_flags += VOXEL_VIEWER
    if not server_mode:
      bot.global_flags -= VISIBLE
    bot

proc glide(unit: Unit, target: Vector3, rotation = 0.0, instant = false) =
  if instant or unit.transform.origin.distance_to(target) >= TELEPORT_DIST:
    unit.move_to(target, rotation)
  else:
    Enu.client.every(33.milliseconds):
      if unit.step_toward(target, rotation, MOVE_SPEED / 30, ANGULAR_SPEED / 30):
        break
  Enu.client.tick

proc run(q: UnitQuery, agent_id = "", flag_errors = true): string =
  Enu.client.online:
    let answered =
      try:
        bot_for(agent_id).ask(q)
      except SessionLost:
        bot_for(agent_id).ask(q)
    # A genuine query failure (transport, timeout, VM fault) arrives in
    # `error` — surface it as a tool error. `eval` opts out (flag_errors =
    # false): its results, errors and all, are returned verbatim for the agent.
    if flag_errors and answered.error != "":
      mark_tool_error()
    answer answered

proc eval_query(code: string, top_level = false, unit_id = ""): UnitQuery =
  UnitQuery(kind: EVAL, code: code, top_level: top_level, unit_id: unit_id)

let enu_server = mcp_server("enu", "1.0.0"):
  mcp_tool:
    proc screenshot(agent_id: string = ""): string =
      ## Screenshot from your bot's view. Returns the saved PNG's path.
      run UnitQuery(kind: SCREENSHOT), agent_id

  mcp_tool:
    proc screenshot_from_player(with_ui: bool = false): string =
      ## Screenshot from the player's camera. Returns the saved PNG's path.
      ## - with_ui: include the UI overlay (default false = just the world).
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
    proc clear_console(): string =
      ## Empty the Enu console.
      run UnitQuery(kind: CLEAR_CONSOLE)

  mcp_tool:
    proc wait_for_script(unit_id: string, timeout: float = 30.0): string =
      ## Reload `unit_id`'s script if it changed, then wait (up to `timeout`s)
      ## for it to finish running and rendering. Returns the unit's world
      ## bounds, or its error. Animated builds never finish — pass a short
      ## timeout and expect "still running" (alive, not stuck).
      Enu.client.online:
        let deadline = get_mono_time() + timeout.seconds

        let r = bot_for().ask(UnitQuery(kind: PING))
        if r.error != "":
          mark_tool_error()
          return r.error
        let unit = Enu.find_unit(unit_id)
        if unit.is_nil:
          mark_tool_error()
          return "Error: unit not found: " & unit_id
        if not Enu.client.tick_until(
          timeout.seconds, SCRIPT_RUNNING notin unit.global_flags
        ):
          mark_tool_error()
          return "Error: " & unit_id & " still running after " & $timeout & "s"
        for error in unit.errors:
          mark_tool_error()
          return
            "Error: " & error.msg &
            (if error.location != "": " at " & error.location
            else: "")

        var settled_streak = 0
        var last_pending = ""
        while settled_streak < 3:
          let p = bot_for().ask(
              eval_query \"""
              let u = find_by_id("{unit_id}")
              if u.is_nil:
                "0"
              else:
                $u.pending_block_updates
            """.dedent.strip
            )
          if p.error != "":
            break
          last_pending = p.result.strip
          if last_pending == "0":
            inc settled_streak
          else:
            settled_streak = 0
          if settled_streak < 3:
            if get_mono_time() > deadline:
              mark_tool_error()
              return
                "Error: " & unit_id & " still rendering after " & $timeout &
                "s (" & last_pending & " block updates pending)"
            discard Enu.client.tick_until(init_duration(milliseconds = 100), false)
        let b = bot_for().ask(
            eval_query \"""
          let u = find_by_id("{unit_id}")
          if u.is_nil:
            ""
          else:
            var b = u.bounds
            "bounds: " & $b.min & " .. " & $b.max
        """.dedent.strip
          )
        if b.error == "": b.result else: ""

  mcp_tool:
    proc eval(
        code: string, top_level: bool = false, unit_id: string = ""
    ): string =
      ## Evaluate Nim code in Enu's VM; returns the value, or "Error: ...".
      ## - top_level: run as module-level code (imports, top-level defs);
      ##   returns nothing. Default false runs in a block with a return value.
      ## - unit_id: run in that unit's script context. Default = the player.
      run(eval_query(code, top_level, unit_id), flag_errors = false)

  mcp_tool:
    proc get_level_dir(): string =
      ## Get the directory path of the currently loaded level.
      run UnitQuery(kind: LEVEL_DIR)

  mcp_tool:
    proc get_block_log(): string =
      ## Blocks the player recently placed or erased by hand, oldest first —
      ## the human's way to point the agent at spots ("delete what I marked
      ## red"). One entry per line; cleared on save_and_reload.
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
      ## Units within `radius` of (x, y, z), nearest first, one per line.
      run eval_query(\"units_near({x}, {y}, {z}, {radius})")

  mcp_tool:
    proc screenshot_top_down(
        x: float, z: float, size: float = 30.0, agent_id: string = ""
    ): string =
      ## Orthographic top-down screenshot centered on (x, z). `size` is the
      ## half-extent shown, in voxels (default 30 → a 60×60 area). Returns
      ## the saved PNG's path.
      Enu.client.online:
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
      ## Framed screenshot of (x, y, z): the bot moves `distance` back,
      ## `height` up, and `angle`° around it (0 = south, 90 = east,
      ## 180 = north) then looks at it. Returns the saved PNG's path.
      Enu.client.online:
        let
          target = vec3(x, y, z)
          bot = bot_for(agent_id)
          pose = frame(target, distance, height, angle)
        bot.glide(pose.pos, pose.yaw_deg, instant = not server_mode)
        bot.look_at(target)
      run UnitQuery(kind: SCREENSHOT), agent_id

  mcp_tool:
    proc move_unit(id: string, x, y, z: float): string =
      ## Move a unit to (x, y, z) and persist it (survives reload), unlike
      ## set_position which only moves the live unit.
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
      ## Delete a unit and its on-disk script/data. Cannot be undone —
      ## prefer move_unit if it might just be misplaced.
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
      ## Glide a unit to (x, y, z) (teleports if over 500 units away).
      ## - rotation: Y-axis rotation in degrees.
      ## - id: unit to move (default: your bot; pass the player's id to move it).
      Enu.client.online:
        let unit =
          if id == "":
            Unit(bot_for(agent_id))
          else:
            Enu.find_unit(id)
        if unit.is_nil:
          mark_tool_error()
          return "Error: Unit not found: " & id
        unit.glide(vec3(x, y, z), rotation, instant = not server_mode)
        ""

proc remove_bots() =
  if Enu.client.connected:
    for unit in Enu.units.value:
      if unit.id.starts_with("mcp_bot-" & ctx_id):
        Enu.units -= unit
    Enu.client.flush

if server_mode:
  Enu.client(id = ctx_id).connect
  info "enu mcp started", pid = get_current_process_id(), address = Enu.client.address
  new_stdio_transport().serve(
    enu_server,
    idle = proc() =
      Enu.client.tick,
  )
elif cli_args.len == 0 or cli_args[0] in ["help", "--help", "-h"]:
  echo "enu — drive a running Enu from the command line.\n"
  echo enu_server.help_text("enu")
  echo "\nRun as an MCP server with: enu mcp"
else:
  proc connect_to_enu(): bool {.gcsafe.} =
    Enu.client(id = ctx_id).connect
    result = Enu.client.tick_until(3.seconds, Enu.client.connected)
    if not result:
      stderr.write_line "Error: can't reach Enu at " & Enu.client.address &
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
