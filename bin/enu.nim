import std/[os, strutils, math]
import pkg/nimcp
import client
import core, models/[bots, things, colors]

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
  if not Enu.client.prev.is_nil and "root_things" in Enu.client.prev:
    for thing in EdSeq[Thing](Enu.client.prev["root_things"]):
      if thing.id == id and ?thing.transform_value:
        return thing.transform

proc bot_for(agent_id = ""): Bot =
  Enu.things.get_or_init(Bot, bot_id(agent_id)):
    let pos = last_transform(bot_id(agent_id)).origin
    let bot = Bot.init(pos.x, pos.y, pos.z, id = bot_id(agent_id))
    bot.color = col(bot.id.hash)
    bot.global_flags += VOXEL_VIEWER
    if not server_mode:
      bot.global_flags -= VISIBLE
    bot

proc glide(thing: Thing, target: Vector3, rotation = 0.0, instant = false) =
  if instant or thing.transform.origin.distance_to(target) >= TELEPORT_DIST:
    thing.move_to(target, rotation)
  else:
    Enu.client.every(33.milliseconds):
      if thing.step_toward(target, rotation, MOVE_SPEED / 30, ANGULAR_SPEED / 30):
        break
  Enu.client.tick

proc run(q: ThingQuery, agent_id = "", flag_errors = true): string =
  if not Enu.client.connected:
    if flag_errors:
      mark_tool_error()
    return "Error: not connected to Enu — call connect or launch_and_connect first"
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

proc eval_query(code: string, top_level = false, thing_id = ""): ThingQuery =
  ThingQuery(kind: EVAL, code: code, top_level: top_level, thing_id: thing_id)

let enu_server = mcp_server("enu", "1.0.0"):
  mcp_tool:
    proc screenshot(agent_id: string = ""): string =
      ## Screenshot from your bot's view. Returns the saved PNG's path.
      run ThingQuery(kind: SCREENSHOT), agent_id

  mcp_tool:
    proc screenshot_from_player(with_ui: bool = false): string =
      ## Screenshot from the player's camera. Returns the saved PNG's path.
      ## - with_ui: include the UI overlay (default false = just the world).
      run ThingQuery(
        kind: SCREENSHOT,
        screenshot_from_player: not with_ui,
        screenshot_with_ui: with_ui,
      )

  mcp_tool:
    proc get_console(): string =
      ## Get the current Enu console output.
      run ThingQuery(kind: CONSOLE)

  mcp_tool:
    proc clear_console(): string =
      ## Empty the Enu console.
      run ThingQuery(kind: CLEAR_CONSOLE)

  mcp_tool:
    proc wait_for_script(thing_id: string, timeout: float = 30.0): string =
      ## Reload `thing_id`'s script if it changed, then wait (up to `timeout`s)
      ## for it to finish running and rendering. Returns the thing's world
      ## bounds, or its error. Animated builds never finish — pass a short
      ## timeout and expect "still running" (alive, not stuck).
      Enu.client.online:
        let deadline = get_mono_time() + timeout.seconds

        let r = bot_for().ask(ThingQuery(kind: PING))
        if r.error != "":
          mark_tool_error()
          return r.error
        let thing = Enu.find_thing(thing_id)
        if thing.is_nil:
          mark_tool_error()
          return "Error: thing not found: " & thing_id
        if not Enu.client.tick_until(
          timeout.seconds, SCRIPT_RUNNING notin thing.global_flags
        ):
          mark_tool_error()
          return "Error: " & thing_id & " still running after " & $timeout & "s"
        for error in thing.errors:
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
              let u = find_by_id({thing_id.escape})
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
                "Error: " & thing_id & " still rendering after " & $timeout &
                "s (" & last_pending & " block updates pending)"
            discard Enu.client.tick_until(init_duration(milliseconds = 100), false)
        let b = bot_for().ask(
            eval_query \"""
          let u = find_by_id({thing_id.escape})
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
        code: string, top_level: bool = false, thing_id: string = ""
    ): string =
      ## Evaluate Nim code in Enu's VM; returns the value, or "Error: ...".
      ## - top_level: run as module-level code (imports, top-level defs);
      ##   returns nothing. Default false runs in a block with a return value.
      ## - thing_id: run in that thing's script context. Default = the player.
      run(eval_query(code, top_level, thing_id), flag_errors = false)

  mcp_tool:
    proc get_level_dir(): string =
      ## Get the directory path of the currently loaded level.
      run ThingQuery(kind: LEVEL_DIR)

  mcp_tool:
    proc get_block_log(): string =
      ## Blocks the player recently placed or erased by hand, oldest first —
      ## the human's way to point the agent at spots ("delete what I marked
      ## red"). One entry per line; cleared on save_and_reload.
      run eval_query("block_log(active_thing())")

  mcp_tool:
    proc clear_block_log(): string =
      ## Empty the block log so subsequent placements start a fresh
      ## annotation session.

      run eval_query \"""
        clear_block_log(active_thing())
        "cleared"
      """.dedent.strip

  mcp_tool:
    proc things_near(x, y, z: float, radius: float = 30.0): string =
      ## Things within `radius` of (x, y, z), nearest first, one per line.
      run eval_query(\"things_near({x}, {y}, {z}, {radius})")

  mcp_tool:
    proc screenshot_top_down(
        x: float, z: float, size: float = 30.0, agent_id: string = ""
    ): string =
      ## Orthographic top-down screenshot centered on (x, z). `size` is the
      ## half-extent shown, in voxels (default 30 → a 60×60 area). Returns
      ## the saved PNG's path.
      Enu.client.online:
        bot_for(agent_id).glide(vec3(x, 1.0, z), instant = not server_mode)
      run ThingQuery(
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
      run ThingQuery(kind: SCREENSHOT), agent_id

  mcp_tool:
    proc move_thing(id: string, x, y, z: float): string =
      ## Move a thing to (x, y, z) and persist it (survives reload), unlike
      ## set_position which only moves the live thing.
      run eval_query \"""
        let u = find_by_id({id.escape})
        if u.is_nil:
          "Error: thing not found: " & {id.escape}
        else:
          u.start_position = vec3({x}, {y}, {z})
          u.position = vec3({x}, {y}, {z})
          "moved " & u.id
      """.dedent.strip

  mcp_tool:
    proc delete_thing(id: string): string =
      ## Delete a thing and its on-disk script/data. Cannot be undone —
      ## prefer move_thing if it might just be misplaced.
      run eval_query \"""
        let u = find_by_id({id.escape})
        if u.is_nil:
          "Error: thing not found: " & {id.escape}
        else:
          u.delete()
          "deleted " & {id.escape}
      """.dedent.strip

  mcp_tool:
    proc set_position(
        x, y, z: float,
        rotation: float = 0.0,
        id: string = "",
        agent_id: string = "",
    ): string =
      ## Glide a thing to (x, y, z) (teleports if over 500 things away).
      ## - rotation: Y-axis rotation in degrees.
      ## - id: thing to move (default: your bot; pass the player's id to move it).
      Enu.client.online:
        let thing =
          if id == "":
            Thing(bot_for(agent_id))
          else:
            Enu.find_thing(id)
        if thing.is_nil:
          mark_tool_error()
          return "Error: Thing not found: " & id
        thing.glide(vec3(x, y, z), rotation, instant = not server_mode)
        ""

  mcp_tool:
    proc connect(address: string = ""): string =
      ## Attach to a running Enu. `address` defaults to $ENU_CONNECT_ADDRESS,
      ## then 127.0.0.1 (ed's default port). The Enu must be listening (started
      ## with --listen). Use when collaborating with a user who has Enu open.
      if Enu.connect(address, id = ctx_id):
        "connected to " & Enu.client.address
      else:
        mark_tool_error()
        "Error: no Enu listening at " &
          (if address != "": address else: "the default address") &
          " — is it running and started with --listen?"

  mcp_tool:
    proc launch_and_connect(level_dir: string): string =
      ## Launch your own private Enu opening `level_dir` (random free port,
      ## minimized) and connect to it. Use when working solo. The instance is
      ## killed on disconnect or when the server exits.
      try:
        "connected to " & Enu.launch_and_connect(level_dir, id = ctx_id)
      except CatchableError as e:
        mark_tool_error()
        "Error: " & e.msg

  mcp_tool:
    proc disconnect(): string =
      ## Disconnect from Enu. If you launched it with launch_and_connect, this
      ## kills it too.
      Enu.disconnect
      "disconnected"

proc remove_bots() =
  if Enu.client.connected:
    for thing in Enu.things.value:
      if thing.id.starts_with("mcp_bot-" & ctx_id):
        Enu.things -= thing
    Enu.client.flush

if server_mode:
  # Create the client but DON'T connect here — connecting to an absent peer in
  # PARTIAL (blocking) mode would block the main thread, so serve() would never
  # run and clients couldn't even handshake. The server must always come up; the
  # agent attaches with the connect / launch_and_connect tools. Only tick the
  # client once we actually have a connection (ticking while down would block on
  # the same reconnect).
  discard Enu.client(id = ctx_id)
  info "enu mcp started", pid = get_current_process_id(), address = Enu.client.address
  new_stdio_transport().serve(
    enu_server,
    idle = proc() =
      if Enu.client.connected:
        Enu.client.tick,
  )
  # Don't orphan a managed Enu when serve returns.
  Enu.disconnect
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
