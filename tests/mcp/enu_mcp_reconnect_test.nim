## Reconnect test for enu_mcp.
##
## Tests that enu_mcp auto-reconnects after the netty connection times out
## (10 seconds of inactivity causes Enu to silently drop the UDP connection).
##
## Run standalone:
##   ENU_CONNECT_ADDRESS=127.0.0.1 nim c -r bin/enu_mcp_reconnect_test.nim
##
## Or via the full suite:
##   ENU_CONNECT_ADDRESS=127.0.0.1 nim c -r bin/enu_mcp_test.nim

import std/[osproc, streams, json, strutils, os, times]

type McpSession = object
  process: Process
  next_id: int

proc open_session(): McpSession =
  result.process = start_process(
    "nim", args = ["r", "./bin/enu.nim", "mcp"], options = {poUsePath}
  )
  result.next_id = 1

proc close(s: var McpSession) =
  s.process.terminate()
  discard s.process.wait_for_exit(timeout = 2000)
  s.process.close()
  sleep 400

proc send(s: McpSession, msg: JsonNode) =
  s.process.input_stream.write($msg & "\n")
  s.process.input_stream.flush()

proc collect_stderr(s: McpSession): string =
  try:
    result = s.process.error_stream.read_all()
  except:
    discard

proc recv(s: McpSession, timeout_ms = 20000): JsonNode =
  let deadline = epoch_time() + timeout_ms.float / 1000.0
  while epoch_time() < deadline:
    let line =
      try:
        s.process.output_stream.read_line()
      except IOError:
        let err = s.collect_stderr()
        echo "FAIL: process died (IOError). stderr (last 3000 chars):"
        echo err[max(0, err.len - 3000) ..< err.len]
        quit 1
    if line == "":
      sleep 10
      continue
    try:
      result = parse_json(line)
    except JsonParsingError:
      # nimcp emits an "MCP server initialized" info line on stdout at boot.
      # Skip non-JSON lines instead of failing the test.
      continue
    return
  let err = s.collect_stderr()
  echo "FAIL: timed out after " & $timeout_ms & "ms. stderr (last 3000 chars):"
  echo err[max(0, err.len - 3000) ..< err.len]
  quit 1

proc send_recv(s: McpSession, msg: JsonNode, timeout_ms = 20000): JsonNode =
  s.send(msg)
  s.recv(timeout_ms)

proc do_initialize(s: var McpSession) =
  let id = s.next_id
  inc s.next_id
  let resp = s.send_recv(
    %*{
      "jsonrpc": "2.0",
      "id": id,
      "method": "initialize",
      "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "test", "version": "1"},
      },
    }
  )
  if resp{"id"}.get_int != id or
      (resp.has_key("error") and resp["error"].kind != JNull):
    echo "FAIL: initialize failed: " & $resp
    quit 1

proc do_call_tool(s: var McpSession, name: string, args: JsonNode, timeout_ms = 20000): string =
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
  if resp{"id"}.get_int != id:
    echo "FAIL: id mismatch in tool response"
    quit 1
  if resp.has_key("error") and resp["error"].kind != JNull:
    return "Error: " & $resp["error"]
  let content = resp{"result"}{"content"}
  if content.kind == JArray and content.len > 0:
    result = content[0]{"text"}.get_str

template check(cond: bool, msg: string) =
  if not cond:
    echo "FAIL: " & msg
    quit 1

proc connect_session(s: var McpSession) =
  ## The server serves without connecting (agents attach explicitly): each
  ## session initializes then calls the connect tool; the empty address
  ## resolves $ENU_CONNECT_ADDRESS.
  s.do_initialize()
  let r = s.do_call_tool("connect", %*{"address": ""})
  check r.starts_with("connected"), "connect: " & r

proc run_reconnect_tests*() =
  echo ""
  echo "Reconnect tests (requires Enu with ENU_LISTEN_ADDRESS=127.0.0.1):"
  discard exec_cmd_ex("pkill -x enu_mcp 2>/dev/null; true")
  sleep 400

  echo "  idle-reconnect: eval, wait 15s for netty timeout, eval again..."
  stdout.flush_file()
  block:
    var s = open_session()
    defer:
      s.close()
    s.connect_session()
    # Send all args: nimcp requires every declared tool param in the JSON,
    # else the call errors `key not found: <param>` (its error JSON happens
    # to contain the requestId, so a bare `"1" in r1` would pass on an
    # error). Full args make this verify eval execution, not just a reply.
    let r1 = s.do_call_tool(
      "eval", %*{"code": "1", "top_level": false, "unit_id": ""}
    )
    check r1 == "1", "initial eval failed: " & r1

    echo "    (waiting 15s for netty 10s timeout + margin...)"
    stdout.flush_file()
    sleep 15_000

    let r2 = s.do_call_tool(
      "eval", %*{"code": "2", "top_level": false, "unit_id": ""},
      timeout_ms = 30_000,
    )
    check r2 == "2", "post-timeout eval failed: " & r2
    echo "  idle-reconnect: PASS"

  echo "  idle-reconnect set_position: connect, wait 15s, move bot..."
  stdout.flush_file()
  block:
    var s = open_session()
    defer:
      s.close()
    s.connect_session()
    let r1 = s.do_call_tool("eval", %*{"code": "1"})
    check "1" in r1, "initial eval failed: " & r1

    echo "    (waiting 15s...)"
    stdout.flush_file()
    sleep 15_000

    let r2 = s.do_call_tool(
      "set_position",
      %*{"x": 3.0, "y": 1.0, "z": -15.0, "rotation": 0.0, "id": ""},
      timeout_ms = 30_000,
    )
    check not r2.starts_with("Error"), "post-timeout set_position failed: " & r2
    echo "  idle-reconnect set_position: PASS"

  echo "  fast-reconnect: 8 fresh sessions back-to-back, no own-message assert..."
  stdout.flush_file()
  # Before the SUBSCRIBE-time stale-sub sweep landed, each fresh enu_mcp
  # process subscribing to Enu within netty's ~10s keepalive window had a
  # ~7/8 chance of tripping the `self.id notin source` assert in ed on the
  # first ASSIGN-publishing tool call (set_position, screenshot_at, eval).
  # With stable per-process ctx ids plus the worker-side sweep on
  # SUBSCRIBE, this loop should run clean.
  for i in 1 .. 8:
    var s = open_session()
    s.connect_session()
    case i mod 4
    of 1:
      let r = s.do_call_tool(
        "set_position",
        %*{"x": 5.0, "y": 1.0, "z": -10.0, "rotation": 0.0, "id": ""},
        timeout_ms = 15_000,
      )
      check not r.starts_with("Error"), "iter " & $i & " set_position: " & r
    of 2:
      let r = s.do_call_tool(
        "screenshot_at",
        %*{
          "x": 0.0, "y": 1.0, "z": -10.0,
          "distance": 20.0, "height": 10.0, "angle": 180.0,
        },
        timeout_ms = 20_000,
      )
      check not r.starts_with("Error"), "iter " & $i & " screenshot_at: " & r
    of 3:
      let r = s.do_call_tool(
        "screenshot_top_down",
        %*{"x": 0.0, "z": -10.0, "size": 30.0},
        timeout_ms = 20_000,
      )
      check not r.starts_with("Error"),
        "iter " & $i & " screenshot_top_down: " & r
    else:
      let r = s.do_call_tool(
        "eval",
        %*{"code": "1", "top_level": false, "unit_id": ""},
        timeout_ms = 15_000,
      )
      check not r.starts_with("Error"), "iter " & $i & " eval: " & r
    s.close()
  echo "  fast-reconnect: PASS"

when is_main_module:
  echo "=== enu_mcp reconnect test ==="
  run_reconnect_tests()
  echo ""
  echo "=== All reconnect tests passed ==="
