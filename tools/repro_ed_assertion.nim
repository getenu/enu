## Reproduce the `self.id notin source` assert in
## deps/ed/src/ed/components/subscriptions.nim:511 by running multiple
## fresh enu mcp sessions and checking whether the first ASSIGN message
## after a new EdContext loops back to the originator.
##
## Run with Enu already up on ENU_LISTEN_ADDRESS=127.0.0.1:
##   ENU_CONNECT_ADDRESS=127.0.0.1 nim r tools/repro_ed_assertion.nim
##
## Each iteration:
##   1. Open a fresh enu mcp session (start_process "nim r bin/enu.nim mcp")
##   2. initialize
##   3. eval "1"  — confirms basic eval round-trip
##   4. set_position — first bot.transform = on a new EdContext
##   5. eval "2"  — confirms post-set_position eval
##
## Reports which step (if any) returns the AssertionDefect.

import std/[osproc, streams, json, strutils, os, times, strformat]

type McpSession = object
  process: Process
  next_id: int
  stderr_buf: string

proc open_session(): McpSession =
  result.process = start_process(
    "nim", args = ["r", "./bin/enu.nim", "mcp"], options = {poUsePath}
  )
  result.next_id = 1

proc close(s: var McpSession) =
  s.process.terminate()
  discard s.process.wait_for_exit(timeout = 2000)
  s.process.close()
  # Give Enu time to detect the disconnect before the next session.
  sleep 400

proc drain_stderr(s: var McpSession) =
  try:
    let chunk = s.process.error_stream.read_all()
    if chunk.len > 0:
      s.stderr_buf &= chunk
  except:
    discard

proc send(s: McpSession, msg: JsonNode) =
  s.process.input_stream.write($msg & "\n")
  s.process.input_stream.flush()

proc recv(s: var McpSession, timeout_ms = 8000): JsonNode =
  let deadline = epoch_time() + timeout_ms.float / 1000.0
  while epoch_time() < deadline:
    let line =
      try:
        s.process.output_stream.read_line()
      except IOError:
        s.drain_stderr()
        raise new_exception(IOError, "process died")
    if line == "":
      sleep 10
      continue
    try:
      return parse_json(line)
    except JsonParsingError:
      # Non-JSON stdout from enu_mcp — log it and keep reading.
      echo "  (non-JSON stdout): " & line[0 ..< min(200, line.len)]
      continue
  s.drain_stderr()
  raise new_exception(IOError, "timeout")

proc send_recv(s: var McpSession, msg: JsonNode, timeout_ms = 8000): JsonNode =
  s.send(msg)
  s.recv(timeout_ms)

proc do_initialize(s: var McpSession) =
  let id = s.next_id
  inc s.next_id
  discard s.send_recv(
    %*{
      "jsonrpc": "2.0",
      "id": id,
      "method": "initialize",
      "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "repro", "version": "1"},
      },
    }
  )

proc do_call_tool(
    s: var McpSession, name: string, args: JsonNode, timeout_ms = 12000
): tuple[ok: bool, text: string, error: string] =
  let id = s.next_id
  inc s.next_id
  let resp = s.send_recv(
    %*{
      "jsonrpc": "2.0",
      "id": id,
      "method": "tools/call",
      "params": {"name": name, "arguments": args},
    },
    timeout_ms,
  )
  if resp.has_key("error") and resp["error"].kind != JNull:
    return (false, "", $resp["error"])
  let content = resp{"result"}{"content"}
  if content.kind == JArray and content.len > 0:
    let text = content[0]{"text"}.get_str
    if "subscriptions.nim" in text and "notin source" in text:
      return (false, text, text)
    return (true, text, "")
  # No error and no content — dump the full response for diagnosis.
  echo "    (empty result, raw resp): " & $resp
  (true, "", "")

proc check(name: string, r: tuple[ok: bool, text: string, error: string]): bool =
  echo &"  {name} ok={r.ok} text={r.text[0 ..< min(80, r.text.len)]}"
  if not r.ok:
    echo &"    err={r.error}"
  if not r.ok and "notin source" in r.error:
    echo &"  REPRODUCED at {name}"
    return true
  false

proc run_iteration(i: int): bool =
  ## Returns true on assert reproduction.
  echo &"=== iteration {i} ==="
  var s = open_session()
  defer:
    s.close()

  s.do_initialize()
  echo "  initialize: ok"

  # Probe each bot-moving tool fresh. Iteration `i` picks which one:
  case i mod 4
  of 1:
    let r = s.do_call_tool(
      "screenshot_top_down",
      %*{"x": 0.0, "z": -10.0, "size": 30.0},
      timeout_ms = 15000,
    )
    if check("screenshot_top_down (cold)", r): return true
  of 2:
    let r = s.do_call_tool(
      "set_position",
      %*{"x": 5.0, "y": 1.0, "z": -10.0, "rotation": 0.0, "id": ""},
      timeout_ms = 15000,
    )
    if check("set_position (cold)", r): return true
  of 3:
    let r = s.do_call_tool(
      "screenshot_at",
      %*{
        "x": 0.0, "y": 1.0, "z": -10.0,
        "distance": 20.0, "height": 10.0, "angle": 180.0,
      },
      timeout_ms = 15000,
    )
    if check("screenshot_at (cold)", r): return true
  else:
    let r = s.do_call_tool(
      "eval", %*{"code": "1", "top_level": false, "unit_id": ""},
      timeout_ms = 15000,
    )
    if check("eval (cold)", r): return true

  false

when is_main_module:
  echo "=== ed assertion reproduction ==="
  var reproduced = 0
  for i in 1..8:
    if run_iteration(i):
      inc reproduced
  echo &"Reproduction: {reproduced}/8 sessions hit the assert"
  if reproduced > 0:
    quit 1
