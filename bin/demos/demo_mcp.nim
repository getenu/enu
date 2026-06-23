import pkg/nimcp
import client, models/[bots, colors]

const CLAUDE_ORANGE = col"d97757"
Enu.client.connect
let bot = Bot.init(0, 0, -150, color = CLAUDE_ORANGE)

Enu.units.add bot

proc reply(q: UnitQuery): string =
  ## A query's answer, flagging a genuine query failure (q.error) as a tool
  ## error. eval bypasses this on purpose — its errors come back as plain
  ## strings for the agent to interpret.
  if q.error != "":
    mark_tool_error()
  answer q

let server = mcp_server("enu-mini", "1.0.0"):
  mcp_tool:
    proc eval(code: string): string =
      ## Evaluates Enu VM code in the player context.
      bot.eval(code)

  mcp_tool:
    proc move(x, y, z: float): string =
      ## Move your bot to (x, y, z).
      let start = bot.position
      let diff = vec3(x, y, z) - start
      Enu.client.animate(1.second):
        bot.position = start + diff * t
      "moved"

  mcp_tool:
    proc rotate(degrees: float): string =
      ## Rotate your bot to `degrees` of yaw.
      let start = bot.rotation
      let diff = degrees - start
      Enu.client.animate(1.second):
        bot.rotation = start + diff * t
      "rotated"

  mcp_tool:
    proc screenshot(): string =
      ## Take a screenshot from your bot's POV. Returns the PNG path.
      reply bot.ask(UnitQuery(kind: SCREENSHOT))

new_stdio_transport().serve(
  server,
  idle = proc() =
    Enu.client.tick,
)
