## Dev-only MCP supervisor, for working on Enu itself (the repo's .mcp.json).
## Shipped worlds run `enu mcp` directly; this never ships.
##
## Claude Code talks to this process, which runs the real server (`bin/enu.nim
## mcp`) as a child built from the current sources. Builds go through `nim r`,
## which hashes every source file and only recompiles when one changed, and
## whose dependency list we watch to rebuild in the background as you edit.
##
## A fresh build replaces the child:
## - when the connected Enu refuses the old one ("Error: version mismatch") --
##   the call is retried on the new child, so it simply succeeds;
## - before a `connect` / `launch_and_connect`;
## - whenever nothing is connected and nothing is in flight.
##
## The session survives a swap: the initialize handshake and the last connect
## are replayed onto the new child, and Claude Code is told if the tool list
## changed. The old child keeps serving until a build succeeds, so a broken
## build never takes the server down. This file imports nothing from Enu, so
## it doesn't go stale itself.

import std/[os, osproc, json, strutils, times, tables, streams]
import std/posix except Time

const
  REPO = current_source_path().parent_dir.parent_dir
  MISMATCH = "Error: version mismatch"
  EOF_MARK = "\0eof"
  INTERNAL = "mcp_dev-"
  BIN_PREFIX = "enu_mcp-"
  STALE_CHECK = init_duration(seconds = 2)
  REPLY_TIMEOUT = init_duration(seconds = 120)

let
  cache_dir = get_cache_dir("enu") / "mcp_dev"
  nimcache = cache_dir / "nimcache"
  build_out = nimcache / "enu_mcp"
  build_log = cache_dir / "build.log"
  server_log = cache_dir / "server.log"

type
  Inbox = ptr Channel[string]

  Child = ref object
    process: Process
    bin: string
    inbox: Inbox
    reader: Thread[(FileHandle, Inbox)]
    dead: bool

var
  child: Child
  ready_bin = ""
    ## The newest successful build, copied out of nimcache (per process) so a
    ## rebuild never rewrites a running binary.
  build: Process
  build_started: Time
  built_mtime: Time
  build_lock: cint
    ## Sessions in the same checkout share the nimcache; `lockf` keeps their
    ## builds from overlapping, and the OS drops it if we die.
  deps: seq[string]
    ## Every file the last build read (from nim's own dependency list).
  last_dep_check: Time
  init_request: JsonNode
  initialized_note: JsonNode
  last_connect: JsonNode
    ## The last successful connect / launch_and_connect call, replayed onto a
    ## new child. nil when not connected.
  tools_seen: JsonNode
  pending: OrderedTable[string, JsonNode]
  resent: Table[string, int]
  internal_id = 0

proc log(msg: string) =
  stderr.write_line "[mcp_dev] " & msg

proc read_lines(args: (FileHandle, Inbox)) {.thread.} =
  let (handle, inbox) = args
  var f: File
  if f.open(handle, fmRead):
    var line: string
    try:
      while f.read_line(line):
        if line.strip.len > 0:
          inbox[].send(line)
    except IOError:
      discard
  inbox[].send(EOF_MARK)

proc new_inbox(): Inbox =
  result = cast[Inbox](alloc_shared0(sizeof(Channel[string])))
  result[].open()

proc free_inbox(inbox: Inbox) =
  inbox[].close()
  dealloc_shared(inbox)

proc parse(line: string): JsonNode =
  try:
    parse_json(line)
  except JsonParsingError:
    log "ignoring non-JSON line: " & line
    nil

proc reply(msg: JsonNode) =
  stdout.write($msg & "\n")
  stdout.flush_file

proc send(c: Child, msg: JsonNode) =
  c.process.input_stream.write($msg & "\n")
  c.process.input_stream.flush

proc tool_name(msg: JsonNode): string =
  if msg{"method"}.get_str == "tools/call":
    msg{"params", "name"}.get_str
  else:
    ""

proc is_connect(msg: JsonNode): bool =
  msg.tool_name in ["connect", "launch_and_connect"]

proc is_error(response: JsonNode): bool =
  response{"result", "isError"}.get_bool or response.has_key("error")

proc is_mismatch(response: JsonNode): bool =
  for item in response{"result", "content"}.get_elems:
    if item{"text"}.get_str.starts_with(MISMATCH):
      return true

proc key(msg: JsonNode): string =
  if msg.has_key("id"): $msg["id"] else: ""

proc next_id(): JsonNode =
  inc internal_id
  %(INTERNAL & $internal_id)

proc fail(request: JsonNode, reason: string) =
  reply(
    %*{
      "jsonrpc": "2.0",
      "id": request["id"],
      "error": {"code": -32603, "message": reason},
    }
  )

proc track(request, response: JsonNode) =
  ## Keep what a swap needs to replay, then hand the response to Claude Code.
  if request.is_connect:
    last_connect = if response.is_error: nil else: request
  elif request.tool_name == "disconnect":
    last_connect = nil
  case request{"method"}.get_str
  of "initialize":
    # Advertise listChanged so a swap can announce a changed tool list.
    if response{"result", "capabilities"}.kind == JObject:
      response["result"]["capabilities"]["tools"] = %*{"listChanged": true}
  of "tools/list":
    tools_seen = response{"result", "tools"}
  else:
    discard
  resent.del request.key
  reply(response)

# --- Builds ---------------------------------------------------------------

proc start_build(wait_for_lock: bool): bool =
  if lockf(build_lock, if wait_for_lock: F_LOCK else: F_TLOCK, 0) != 0:
    return false # another session is building; its output will be ours too
  build_started = get_time()
  let cmd =
    "exec nim r --hints:off --warnings:off --nimcache:" & quote_shell(nimcache) &
    " -o:" & quote_shell(build_out) & " bin/enu.nim help > " &
    quote_shell(build_log) & " 2>&1"
  build = start_process("/bin/sh", working_dir = REPO, args = ["-c", cmd])
  true

proc finish_build(): bool =
  ## Reap a finished build. On success, note its dependencies and, if it
  ## produced a new binary, copy that out as `ready_bin`.
  let code = build.wait_for_exit
  build.close
  build = nil
  try:
    if code != 0:
      log "build failed (see " & build_log & ")"
      return false
    let info = parse_file(nimcache / "enu_mcp.json")
    deps = @[]
    for dep in info{"depfiles"}.get_elems:
      deps.add dep[0].get_str
    for cfg in info{"configFiles"}.get_elems:
      deps.add cfg.get_str
    let mtime = build_out.get_last_modification_time
    if mtime != built_mtime or ready_bin == "":
      built_mtime = mtime
      ready_bin =
        cache_dir / (BIN_PREFIX & $get_current_process_id() & "-" & $mtime.to_unix)
      copy_file_with_permissions(build_out, ready_bin)
      log "fresh build ready: " & ready_bin.extract_filename
    true
  finally:
    discard lockf(build_lock, F_ULOCK, 0)

proc build_now(): bool =
  ## Bring `ready_bin` up to date, waiting for the build. About a second when
  ## nothing changed: `nim r` only recompiles when a source hash differs.
  if build.is_nil:
    discard start_build(wait_for_lock = true)
  finish_build()

proc sources_changed(): bool =
  for dep in deps:
    try:
      if dep.get_last_modification_time > build_started:
        return true
    except OSError:
      return true # a file went away: the import graph changed

proc remove_orphaned_bins() =
  ## Binary copies left by sessions that are gone.
  for path in walk_files(cache_dir / (BIN_PREFIX & "*")):
    let pid = path.extract_filename[BIN_PREFIX.len ..^ 1].split("-")[0]
    try:
      if kill(Pid(pid.parse_int), 0) != 0:
        remove_file(path)
    except ValueError, OSError:
      discard

# --- Children -------------------------------------------------------------

proc start_child(bin: string): Child =
  result = Child(bin: bin, inbox: new_inbox())
  let cmd = "exec " & quote_shell(bin) & " mcp 2>> " & quote_shell(server_log)
  result.process = start_process("/bin/sh", working_dir = REPO, args = ["-c", cmd])
  create_thread(
    result.reader, read_lines, (result.process.output_handle, result.inbox)
  )

proc stop_child(c: Child) =
  ## Close its stdin so `serve` returns and the child disconnects cleanly (and
  ## stops any Enu it launched), then reap it.
  try:
    c.process.input_stream.close
  except IOError, OSError:
    discard
  if c.process.wait_for_exit(timeout = 5000) == -1 or c.process.running:
    c.process.kill
    discard c.process.wait_for_exit
  join_thread(c.reader)
  c.process.close
  free_inbox(c.inbox)
  if c.bin != ready_bin:
    try:
      remove_file(c.bin)
    except OSError:
      discard

proc await_reply(c: Child, id: JsonNode): JsonNode =
  ## Wait for the child's response to `id`. Anything else that arrives
  ## meanwhile is delivered as usual. nil if the child dies or stalls.
  let deadline = get_time() + REPLY_TIMEOUT
  while get_time() < deadline:
    let (ok, line) = c.inbox[].try_recv
    if not ok:
      sleep 5
      continue
    if line == EOF_MARK:
      c.dead = true
      return nil
    let msg = parse(line)
    if msg.is_nil:
      continue
    if msg{"id"} == id:
      return msg
    if msg.key in pending:
      let request = pending[msg.key]
      pending.del msg.key
      track(request, msg)
    else:
      reply(msg)

proc ask(c: Child, msg: JsonNode): JsonNode =
  var request = msg.copy
  request["id"] = next_id()
  c.send(request)
  c.await_reply(request["id"])

proc swap_to(bin: string, replay_connect: bool) =
  ## Replace the child with one running `bin`, carrying the session over.
  log "starting " & bin.extract_filename
  if not child.is_nil:
    stop_child(child)
  child = start_child(bin)
  if init_request.is_nil:
    return
  discard child.ask(init_request)
  if not initialized_note.is_nil:
    child.send(initialized_note)
  if replay_connect and not last_connect.is_nil:
    let response = child.ask(last_connect)
    if response.is_nil or response.is_error:
      log "replaying the last connect failed; the agent will need to reconnect"
      last_connect = nil
  if not tools_seen.is_nil:
    let tools = child.ask(%*{"jsonrpc": "2.0", "method": "tools/list"})
    if not tools.is_nil and tools{"result", "tools"} != tools_seen:
      tools_seen = tools{"result", "tools"}
      reply(%*{"jsonrpc": "2.0", "method": "notifications/tools/list_changed"})

proc fail_pending(reason: string) =
  for request in pending.values:
    request.fail(reason)
  pending.clear

# --- Message handling -----------------------------------------------------

proc retry_on_fresh_build(request, response: JsonNode): JsonNode =
  ## The Enu refused this child. If a newer build exists (or can be made), swap
  ## to it and retry; otherwise the Enu is the stale side -- pass the error on.
  if not build_now() or ready_bin == child.bin:
    return response
  fail_pending("interrupted while the Enu MCP server restarted; retry")
  swap_to(ready_bin, replay_connect = not request.is_connect)
  child.send(request)
  result = child.await_reply(request["id"])
  if result.is_nil:
    result = response

proc handle_child_message(line: string) =
  let msg = parse(line)
  if msg.is_nil:
    return
  if msg.key notin pending:
    reply(msg)
    return
  let request = pending[msg.key]
  pending.del msg.key
  if msg.is_mismatch:
    track(request, retry_on_fresh_build(request, msg))
  else:
    track(request, msg)

proc restart_dead_child() =
  ## The child exited unexpectedly. Restart it and resend what was in flight,
  ## once each -- a request that crashes it twice gets an error instead.
  log "child exited; restarting"
  var retry: seq[JsonNode]
  for key, request in pending:
    if resent.get_or_default(key) == 0:
      retry.add request
    else:
      request.fail("the Enu MCP server crashed handling this request")
      resent.del key
  pending.clear
  swap_to(if ready_bin != "": ready_bin else: child.bin, replay_connect = true)
  for request in retry:
    resent[request.key] = 1
    pending[request.key] = request
    child.send(request)

proc handle_client_message(line: string) =
  let msg = parse(line)
  if msg.is_nil:
    return
  case msg{"method"}.get_str
  of "initialize":
    init_request = msg
  of "notifications/initialized":
    initialized_note = msg
  else:
    discard
  if msg.is_connect and ready_bin != child.bin and pending.len == 0:
    # A fresh connect is the natural moment to pick up a newer build.
    swap_to(ready_bin, replay_connect = false)
  if msg.has_key("id"):
    pending[msg.key] = msg
  child.send(msg)

proc tend_builds() =
  ## Rebuild in the background as sources change, and swap to a fresh build
  ## whenever that can't disturb anything: nothing connected, nothing in
  ## flight. A connected session swaps on its next mismatch or connect instead.
  let now = get_time()
  if not build.is_nil:
    if build.peek_exit_code != -1:
      discard finish_build()
  elif now - last_dep_check >= STALE_CHECK:
    last_dep_check = now
    if sources_changed():
      discard start_build(wait_for_lock = false)
  if ready_bin != child.bin and last_connect.is_nil and pending.len == 0 and
      not init_request.is_nil:
    swap_to(ready_bin, replay_connect = false)

proc main() =
  create_dir(cache_dir)
  build_lock = posix.open(cstring(cache_dir / "build.lock"), O_CREAT or O_RDWR, 0o644)
  remove_orphaned_bins()
  if not build_now():
    quit "[mcp_dev] couldn't build bin/enu.nim; see " & build_log
  child = start_child(ready_bin)

  var stdin_reader: Thread[(FileHandle, Inbox)]
  let client = new_inbox()
  create_thread(stdin_reader, read_lines, (FileHandle(0), client))

  while true:
    var busy = false
    let (got_client, client_line) = client[].try_recv
    if got_client:
      busy = true
      if client_line == EOF_MARK:
        break
      handle_client_message(client_line)
    while not child.dead:
      let (got, line) = child.inbox[].try_recv
      if not got:
        break
      busy = true
      if line == EOF_MARK:
        child.dead = true
      else:
        handle_child_message(line)
    if child.dead:
      restart_dead_child()
    tend_builds()
    if not busy:
      sleep 5

  stop_child(child)
  try:
    remove_file(child.bin)
  except OSError:
    discard
  if not build.is_nil:
    build.terminate
    build.close

main()
