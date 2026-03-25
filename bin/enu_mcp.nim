import std/[os, monotimes]
import std/times as std_times
import pkg/[ed, nimcp]
import models

var
  mcp_query: EdValue[McpQuery]
  connect_addr = get_env("ENU_CONNECT_ADDRESS", "127.0.0.1")
  log_file: File

proc log(msg: string) =
  if log_file != nil:
    log_file.write_line std_times.now().format("HH:mm:ss'.'fff") & " " & msg
    log_file.flush_file()

proc try_connect() =
  {.gcsafe.}:
    log "connecting to Enu at " & connect_addr
    try:
      Ed.thread_ctx.subscribe(connect_addr)
      log "connected"
    except CatchableError as e:
      let msg = "Not connected to Enu (" & connect_addr & "): " & e.msg
      stderr.write_line msg
      log "connect failed: " & e.msg

const TOOL_TIMEOUT_MS = 30_000

proc run_tool(kind: McpQueryKind, code = ""): string =
  log "run_tool kind=" & $kind & " code=" & code[0 ..< min(80, code.len)]
  {.gcsafe.}:
    # Tick first to process any pending messages and detect dropped connections
    Ed.thread_ctx.tick

    if Ed.thread_ctx.subscribers.len == 0:
      try_connect()
    if Ed.thread_ctx.subscribers.len == 0:
      log "aborting: not connected"
      quit(1)

    mcp_query.value = McpQuery(kind: kind, code: code)
    log "request set, entering poll loop"

    let start = get_mono_time()
    while true:
      Ed.thread_ctx.tick
      let v = mcp_query.value
      let elapsed = (get_mono_time() - start).in_milliseconds
      if v.done:
        log "done, result=" & v.result[0 ..< min(80, v.result.len)]
        return if v.error != "": v.error else: v.result
      elif elapsed > TOOL_TIMEOUT_MS:
        log "timeout after " & $elapsed & "ms — exiting"
        quit(1)
      sleep 10

let enu_server = mcp_server("enu", "1.0.0"):
  mcp_tool:
    proc screenshot(): string =
      ## Take a screenshot of the current Enu viewport.
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

let log_path = get_temp_dir() / "enu_mcp.log"
discard open(log_file, log_path, fmAppend)
log "=== enu_mcp starting, pid=" & $get_current_process_id() &
  " connect_addr=" & connect_addr & " log=" & log_path

Ed.bootstrap

let mcp_ctx = EdContext.init(id = "enu_mcp", chan_size = 100, buffer = false, label = "enu-mcp")
Ed.thread_ctx = mcp_ctx
log "Ed context initialized"

# Initialize the query object BEFORE subscribing so:
# 1. McpQuery type is registered in type_initializers (compile-time via create_initializer)
# 2. The object exists in our ctx with a known state before Enu sees us
# done: true so the initial subscribe-time push doesn't trigger the worker
mcp_query = EdValue[McpQuery].init(McpQuery(done: true), id = "mcp_query")
log "mcp_query initialized"

try_connect()
log "starting stdio server"

new_stdio_transport().serve(enu_server)
