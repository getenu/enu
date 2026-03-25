## Test harness for enu_mcp. Run with:
##   nim c -r bin/enu_mcp_test.nim
##
## Integration tests (eval/screenshot/get_console) require Enu running with:
##   ENU_LISTEN_ADDRESS=127.0.0.1 nim start
##
## Verifies:
##   - All stdout lines are valid JSON (logging to stdout = test failure)
##   - Stderr output does not corrupt stdout
##   - JSON-RPC ids round-trip correctly
##   - Tool results have the expected structure

import std/[osproc, streams, json, strutils, os, times]

type McpSession = object
  process: Process
  next_id: int

proc open_session(): McpSession =
  result.process = start_process(
    "nim", args = ["r", "./bin/enu_mcp.nim"], options = {poUsePath}
  )
  result.next_id = 1

proc close(s: var McpSession) =
  s.process.terminate()
  discard s.process.wait_for_exit(timeout = 2000)
  s.process.close()
  # Give Enu time to detect the disconnect before the next session connects
  sleep 400

proc send(s: McpSession, msg: JsonNode) =
  s.process.input_stream.write($msg & "\n")
  s.process.input_stream.flush()

proc recv(s: McpSession, timeout_ms = 8000): JsonNode =
  let deadline = epoch_time() + timeout_ms.float / 1000.0
  while epoch_time() < deadline:
    let line = s.process.output_stream.read_line()
    if line == "":
      sleep 10
      continue
    # Any non-JSON on stdout is a test failure
    try:
      result = parse_json(line)
    except JsonParsingError as e:
      echo "FAIL: non-JSON on stdout: " & e.msg
      echo "  raw: " & line[0 ..< min(300, line.len)]
      quit 1
    return
  echo "FAIL: timed out after " & $timeout_ms & "ms waiting for response"
  quit 1

proc send_recv(s: McpSession, msg: JsonNode, timeout_ms = 8000): JsonNode =
  s.send(msg)
  s.recv(timeout_ms)

proc check_id(response: JsonNode, id: int) =
  if response{"id"}.get_int != id:
    echo "FAIL: expected id=" & $id & " got id=" & $response{"id"}
    quit 1

proc check_ok(response: JsonNode) =
  if response.has_key("error") and response["error"].kind != JNull:
    echo "FAIL: unexpected error: " & $response["error"]
    quit 1

proc check_error(response: JsonNode) =
  if not (response.has_key("error") and response["error"].kind != JNull):
    echo "FAIL: expected error but got: " & $response
    quit 1

proc do_initialize(s: var McpSession): JsonNode =
  let id = s.next_id
  inc s.next_id
  result = s.send_recv(
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
  result.check_id(id)
  result.check_ok()

proc do_list_tools(s: var McpSession): JsonNode =
  let id = s.next_id
  inc s.next_id
  result = s.send_recv(
    %*{"jsonrpc": "2.0", "id": id, "method": "tools/list", "params": {}}
  )
  result.check_id(id)
  result.check_ok()

proc do_call_tool(
    s: var McpSession, name: string, args: JsonNode, timeout_ms = 12000
): JsonNode =
  let id = s.next_id
  inc s.next_id
  result = s.send_recv(
    %*{
      "jsonrpc": "2.0",
      "id": id,
      "method": "tools/call",
      "params": {"name": name, "arguments": args},
    },
    timeout_ms,
  )
  result.check_id(id)
  result.check_ok()

proc tool_text(response: JsonNode): string =
  let content = response{"result"}{"content"}
  if content.kind != JArray or content.len == 0:
    echo "FAIL: expected content array, got: " & $response
    quit 1
  result = content[0]{"text"}.get_str

# ---- Tests ----------------------------------------------------------------

template test(name: string, body: untyped) =
  stdout.write "  " & name & "... "
  stdout.flush_file()
  block:
    body
  echo "PASS"

proc run_protocol_tests() =
  echo "Protocol tests (no Enu required):"

  test "initialize returns valid protocolVersion":
    var s = open_session()
    defer:
      s.close()
    let resp = s.do_initialize()
    let proto = resp{"result"}{"protocolVersion"}.get_str
    if proto == "":
      echo "FAIL: missing protocolVersion"
      quit 1

  test "initialize serverInfo.name is 'enu'":
    var s = open_session()
    defer:
      s.close()
    let resp = s.do_initialize()
    if resp{"result"}{"serverInfo"}{"name"}.get_str != "enu":
      echo "FAIL: wrong server name"
      quit 1

  test "tools/list returns eval, get_console, screenshot":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    let resp = s.do_list_tools()
    let tools = resp{"result"}{"tools"}
    if tools.kind != JArray:
      echo "FAIL: tools is not an array"
      quit 1
    var names: seq[string]
    for t in tools:
      names.add t{"name"}.get_str
    for expected in ["eval", "get_console", "screenshot"]:
      if expected notin names:
        echo "FAIL: missing tool: " & expected
        quit 1

  test "each tool has description and inputSchema":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    let resp = s.do_list_tools()
    for tool in resp{"result"}{"tools"}:
      let n = tool{"name"}.get_str
      if tool{"description"}.get_str == "":
        echo "FAIL: tool '" & n & "' missing description"
        quit 1
      if not tool.has_key("inputSchema"):
        echo "FAIL: tool '" & n & "' missing inputSchema"
        quit 1

  test "unknown method returns JSON-RPC error":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    let id = s.next_id
    inc s.next_id
    let resp = s.send_recv(
      %*{"jsonrpc": "2.0", "id": id, "method": "no_such_method", "params": {}}
    )
    resp.check_id(id)
    resp.check_error()

  test "multiple initialize calls each return valid responses":
    for _ in 1 .. 3:
      var s = open_session()
      defer:
        s.close()
      let resp = s.do_initialize()
      if resp{"result"}{"protocolVersion"}.get_str == "":
        echo "FAIL: missing protocolVersion"
        quit 1

  test "eval tool has 'code' parameter in schema":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    let resp = s.do_list_tools()
    for tool in resp{"result"}{"tools"}:
      if tool{"name"}.get_str == "eval":
        let props = tool{"inputSchema"}{"properties"}
        if not props.has_key("code"):
          echo "FAIL: eval missing 'code' property"
          quit 1

  test "response ids match request ids":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    # Send two requests, verify ids are correct
    let id1 = s.next_id
    inc s.next_id
    let id2 = s.next_id
    inc s.next_id
    s.send(
      %*{"jsonrpc": "2.0", "id": id1, "method": "tools/list", "params": {}}
    )
    s.send(
      %*{"jsonrpc": "2.0", "id": id2, "method": "tools/list", "params": {}}
    )
    let r1 = s.recv()
    let r2 = s.recv()
    let got = [r1{"id"}.get_int, r2{"id"}.get_int]
    if id1 notin got or id2 notin got:
      echo "FAIL: id mismatch"
      quit 1

proc run_integration_tests() =
  echo ""
  echo "Integration tests (requires Enu with ENU_LISTEN_ADDRESS=127.0.0.1):"
  # Kill any stale enu_mcp processes left from a previous run
  discard exec_cmd_ex("pkill -x enu_mcp 2>/dev/null; true")
  sleep 400

  test "eval: 42 expression returns '42'":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    let text = s.do_call_tool("eval", %*{"code": "42"}).tool_text
    if "42" notin text:
      echo "FAIL: expected '42' in output, got: " & text
      quit 1

  test "eval: 3 sequential calls all succeed":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    for i in 1 .. 3:
      let text = s.do_call_tool("eval", %*{"code": $i}).tool_text
      if $i notin text:
        echo "FAIL: call " & $i & " got: " & text
        quit 1

  test "eval: same session, multiple tool calls stay live":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    for i in 1 .. 5:
      let text =
        s.do_call_tool("eval", %*{"code": "\"ping" & $i & "\""}).tool_text
      if "ping" & $i notin text:
        echo "FAIL: call " & $i & " got: " & text
        quit 1

  test "get_console returns output from prior eval":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    discard s.do_call_tool("eval", %*{"code": "echo \"console_marker_xyz\""})
    let text = s.do_call_tool("get_console", %*{}).tool_text
    if "console_marker_xyz" notin text:
      echo "FAIL: marker not found in console: " & text[
        0 ..< min(200, text.len)
      ]
      quit 1

  test "screenshot returns a .png file path":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    let text = s.do_call_tool("screenshot", %*{}, timeout_ms = 20000).tool_text
    if not text.ends_with(".png"):
      echo "FAIL: expected .png path, got: " & text[0 ..< min(100, text.len)]
      quit 1
    echo "(path: " & text & ") "

  test "screenshot then eval: server stays alive after screenshot":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    discard s.do_call_tool("screenshot", %*{}, timeout_ms = 20000)
    let text =
      s.do_call_tool("eval", %*{"code": "echo after_screenshot"}).tool_text
    if "after_screenshot" notin text:
      echo "FAIL: eval after screenshot failed, got: " & text
      quit 1

  test "eval player.position = vec3(0, 5, -30)":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    let resp = s.do_call_tool(
      "eval",
      %*{"code": "player.position = vec3(0, 5, -30)"},
      timeout_ms = 30000,
    )
    let text = resp.tool_text
    echo "(result: '" & text & "') "

  test "stress: 25 alternating screenshot+eval calls all complete":
    var s = open_session()
    defer:
      s.close()
    discard s.do_initialize()
    for i in 1 .. 25:
      let shot =
        s.do_call_tool("screenshot", %*{}, timeout_ms = 15000).tool_text
      if not shot.ends_with(".png"):
        echo "FAIL: screenshot " & $i & " failed, got: " &
          shot[0 ..< min(80, shot.len)]
        quit 1
      let ev =
        s.do_call_tool("eval", %*{"code": $i}, timeout_ms = 15000).tool_text
      if $i notin ev:
        echo "FAIL: eval " & $i & " got: " & ev[0 ..< min(80, ev.len)]
        quit 1
    echo "(50 tool calls) "

proc run_hang_repro() =
  echo ""
  echo "Hang repro (loops until hang or 100 calls):"
  echo "  eval+screenshot loop..."
  stdout.flush_file()

  var s = open_session()
  defer:
    s.close()
  discard s.do_initialize()

  var call = 0
  while call < 100:
    inc call
    let ev =
      s.do_call_tool("eval", %*{"code": $call}, timeout_ms = 35000).tool_text
    if $call notin ev:
      echo ""
      echo "FAIL: eval " & $call & " got: " & ev[0 ..< min(80, ev.len)]
      quit 1
    stdout.write $call & "e "
    stdout.flush_file()

    let shot = s.do_call_tool("screenshot", %*{}, timeout_ms = 35000).tool_text
    if not shot.ends_with(".png"):
      echo ""
      echo "FAIL: screenshot after eval " & $call & " got: " &
        shot[0 ..< min(80, shot.len)]
      quit 1
    stdout.write $call & "s "
    stdout.flush_file()

  echo ""
  echo "  PASS (500 calls without hang)"

# ---- Main -----------------------------------------------------------------

let is_integration =
  get_env("ENU_CONNECT_ADDRESS", "") != "" or
  get_env("ENU_LISTEN_ADDRESS", "") != ""

echo "=== enu_mcp test suite ==="
echo ""

run_protocol_tests()

if is_integration:
  run_integration_tests()
  run_hang_repro()
else:
  echo ""
  echo "(skipping integration tests — run with ENU_LISTEN_ADDRESS=127.0.0.1)"

echo ""
echo "=== All tests passed ==="
