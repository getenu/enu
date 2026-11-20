## Client-side convenience layer for native apps that drive a running Enu
## over `ed` (the demos under `bin/`, the MCP server). `Enu` is a marker type
## whose "class methods" wrap the boilerplate of standing up an `EdClient` and
## reaching into its context, so an app reads `Enu.client` / `Enu.things`
## instead of spelling out the context plumbing.
##
## This is purely an app-facing helper — regular Enu doesn't use it.

import std/[os, osproc, net, strutils, sequtils, exitprocs]
when not defined(windows):
  from std/posix import kill, Pid, SIGTERM
import pkg/ed
import core, models/things

export ed, core, things

type Enu* = object ## Marker type for the `Enu.*` helpers; never instantiated.

var enu_client {.threadvar.}: EdClient
  ## The thread's client, set by `Enu.client` so the other helpers don't need
  ## a handle threaded through every call.

proc client*(_: type Enu, address = "", mode = PARTIAL, id = ""): EdClient =
  ## This thread's Enu client: created and stored on first call, returned as-is
  ## on every call after — so `Enu.client` is a stable handle you can name
  ## anywhere (`Enu.client.connect`, `Enu.client.tick`, ...) without threading
  ## a variable around (later args are ignored once it exists). `address`
  ## defaults to $ENU_CONNECT_ADDRESS, then "127.0.0.1"; `mode` defaults to
  ## PARTIAL (on-demand, blocking reads) — the right default for a synchronous
  ## tool. It starts unconnected; connect it once with `.connect`, which
  ## bootstraps the Ed runtime at your call site:
  ##
  ##   Enu.client.connect
  if enu_client.is_nil:
    let resolved =
      if address != "":
        address
      else:
        get_env("ENU_CONNECT_ADDRESS", "127.0.0.1")
    enu_client = EdClient(id: id, address: resolved, mode: mode)
  enu_client

var root_things {.threadvar.}: Ed[seq[Thing]]
  ## Held for the session. Without a live reference the evictor reclaims it
  ## between calls, and fetching it again brings every unit with it — tens of
  ## MB, and seconds even on an idle machine.

const ROOT_THINGS_TIMEOUT = 60.seconds

proc things*(_: type Enu): Ed[seq[Thing]] =
  ## The level's top-level things, via this thread's client. The first call
  ## in a session waits for them to arrive.
  let ctx = enu_client.ctx
  if ?root_things and not root_things.destroyed and root_things.ctx == ctx:
    return root_things
  # Not a blocking read: that gives up after a few seconds, which a busy
  # machine can need just to send the units.
  let deadline = get_mono_time() + ROOT_THINGS_TIMEOUT
  var pending = ctx.fetch("root_things")
  while true:
    discard enu_client.tick_until(
      deadline - get_mono_time(), pending.state != Pending
    )
    if pending.state == Found:
      break
    if get_mono_time() >= deadline:
      raise KeyError.init(
        "Enu didn't send its things within " & $ROOT_THINGS_TIMEOUT &
          " (fetch " & $pending.state & ")"
      )
    # NotFound: Enu always has them, so the link dropped (a long level load
    # can hold Enu's worker past the connection timeout). Ask again once
    # it's back.
    discard enu_client.tick_until(250.milliseconds, false)
    pending = enu_client.ctx.fetch("root_things")
  root_things = Ed[seq[Thing]](pending.obj)
  root_things

proc find_thing*(_: type Enu, id: string): Thing =
  ## The root thing with this `id`, or nil if there's no match.
  for thing in Enu.things:
    if thing.id == id:
      return thing

proc ask*(thing: Thing, q: ThingQuery, timeout = 30.seconds): ThingQuery =
  ## File query `q` against `thing` and tick until Enu answers (or `timeout`).
  let slot = thing.query(q)
  if Enu.client.tick_until(timeout, slot.value.state == DONE):
    return slot.value
  thing.query = ThingQuery(state: DONE)
  ThingQuery(state: DONE, error: "Error: Enu did not respond within " & $timeout)

proc answer*(q: ThingQuery): string =
  ## A query's result, or its error message.
  if q.error != "": q.error else: q.result

proc eval*(thing: Thing, code: string, top_level = false): string =
  ## Run Nim `code` in `thing`'s scripting context; return the value or error.
  answer thing.ask(ThingQuery(kind: EVAL, code: code, top_level: top_level))

# --- Managed Enu instances -------------------------------------------------
# Launch and own an Enu process, rather than connecting to one the user is
# running. Backs the MCP server's launch_enu/kill_enu tools and the MCP
# integration tests: an agent (or a test) can stand up a private Enu on a
# random port and tear it down again.

var enu_process {.threadvar.}: Process
  ## The Enu we launched, if any. Only this process may be terminated on
  ## `disconnect` — we never touch an Enu the user is running.
var managed_pid: int
  ## Its pid, for the exit hook (which can run on any thread).
var exit_hook_added: bool
var managed_workdir {.threadvar.}: string

const exe_ext = when defined(windows): ".exe" else: ""

proc free_port(): int =
  ## Ask the OS for a free UDP port on loopback, then release it so the caller
  ## can bind it — avoids colliding with a hard-coded port. (Duplicated from
  ## ed's test_util; will move into ed once its current work settles.)
  let s = new_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  defer:
    s.close()
  s.bind_addr(Port(0), "127.0.0.1")
  int(s.get_local_addr()[1])

proc launch_spec(): tuple[exe, workdir: string, args: seq[string]] =
  ## Where the Enu to launch lives — static per dev/dist build and OS, with an
  ## `ENU_EXE` override. Dev runs the in-tree Godot binary on the game scene; a
  ## dist build runs the packaged executable bundled alongside us.
  when defined(dist):
    let bin_dir = get_app_filename().parent_dir
    when defined(macosx):
      # …/Contents/Resources/bin/enu -> …/Contents/MacOS/Enu
      result =
        (bin_dir.parent_dir.parent_dir / "MacOS" / "Enu", bin_dir.parent_dir, @[])
    elif defined(windows):
      result = (bin_dir / ("enu" & exe_ext), bin_dir, @[])
    else:
      # linux: …/lib/bin/enu -> …/bin/enu  (TODO: confirm dist layout)
      result = (
        bin_dir.parent_dir.parent_dir / "bin" / "enu",
        bin_dir.parent_dir.parent_dir,
        @[],
      )
  else:
    const
      repo = current_source_path().parent_dir.parent_dir
      target =
        when defined(macosx): "osx"
        elif defined(windows): "windows"
        else: "x11"
      cpu = when host_cpu == "arm64": "arm64" else: "64"
      godot =
        repo / "vendor" / "godot" / "bin" /
        ("godot." & target & ".tools." & cpu & exe_ext)
    result = (godot, repo / "app", @["scenes/game.tscn"])
  let override = get_env("ENU_EXE")
  if override != "":
    result.exe = override

proc terminate_managed() =
  ## Stop the Enu we launched, if any. Never touches an Enu the user runs.
  managed_pid = 0
  if not enu_process.is_nil:
    enu_process.terminate()
    discard enu_process.wait_for_exit(timeout = 3000)
    if enu_process.running:
      enu_process.kill()
      discard enu_process.wait_for_exit()
    enu_process.close()
    enu_process = nil
  if managed_workdir != "":
    remove_dir managed_workdir
    managed_workdir = ""

proc disconnect*(_: type Enu) =
  ## Drop the client connection. If we launched the Enu (via launch_and_connect)
  ## terminate it too — we never kill an Enu the user is running. Safe to call
  ## when nothing is connected.
  terminate_managed()
  if not enu_client.is_nil:
    if not enu_client.ctx.is_nil:
      let ctx = enu_client.ctx
      ctx.close
      # `ctx` was adopted as this thread's `Ed.thread_ctx` when we connected. A
      # closed context is spent — ed's own reconnect path mints a fresh context
      # rather than reuse one — so don't leave it installed: the next `connect`'s
      # first-connect path re-adopts `Ed.thread_ctx` whenever the pinned ctx id
      # matches, and re-subscribing on it stands up a fresh reactor while the
      # stale subscriber connections still carry the old reactor's id, tripping
      # netty's `reactor.id == conn.reactorId` assert. Drop it so the next connect
      # starts from a fresh context.
      if Ed.thread_ctx == ctx:
        Ed.thread_ctx = EdContext.init()
    enu_client = nil
  root_things = nil

proc connect*(_: type Enu, address = "", id = ""): bool {.discardable.} =
  ## Attach to a running Enu at `address` (else $ENU_CONNECT_ADDRESS, else
  ## "127.0.0.1" on ed's default port). Drops any current connection / managed
  ## process first; does NOT launch anything. Returns whether it connected. The
  ## target Enu must be listening (started with --listen); the client's
  ## connect_timeout bounds the attempt so an absent peer fails fast. Raises
  ## `SchemaMismatchError` when the Enu refuses us because it was built from
  ## different types.
  Enu.disconnect
  let resolved =
    if address != "": address else: get_env("ENU_CONNECT_ADDRESS", "127.0.0.1")
  Enu.client(address = resolved, id = id).connect
  result = Enu.client.connected
  if not result:
    let refusal = Enu.client.refusal
    Enu.disconnect
    if refusal != "":
      raise SchemaMismatchError.init(refusal)

proc server_ctx_id*(_: type Enu): string =
  ## The connected server's ed context id, from the client's remote
  ## subscription (empty when not connected). A client uses it to author a
  ## unit's script: `unit.code = Code.init(src, runner = Enu.server_ctx_id)`
  ## — the server's code watch only runs a change whose `runner` is its own
  ## context, and a plain client never populates `state.server_ctx_name`.
  for sub in Ed.thread_ctx.subscribers:
    if sub.kind == REMOTE:
      return sub.ctx_id

proc launch_and_connect*(
    _: type Enu,
    world: string,
    level = "",
    id = "",
    timeout = 90.seconds,
    temp_workdir = false,
): string =
  ## Launch a private Enu opening `world` (a path) at level `level` (a name;
  ## empty = the world's initial level) on a random free port (listening,
  ## minimized), connect to it, and return its "host:port" address. The instance
  ## is ours: `disconnect` (or process exit) kills it. `world` is required.
  ## `temp_workdir` runs against a throwaway copy of the world (for tests) so the
  ## source is never modified. Otherwise the world is edited in place, but the
  ## instance keeps its settings in a private dir so it can't overwrite the
  ## user's config. A relative `world` is taken from the current directory.
  if world == "":
    raise ValueError.init("launch_and_connect requires a world")
  Enu.disconnect
  let
    address = "127.0.0.1:" & $free_port()
    port = address.split(':')[^1]
    spec = launch_spec()
    workdir_flags =
      if temp_workdir:
        @["--temp-workdir"]
      else:
        managed_workdir =
          get_temp_dir() / ("enu-mcp-" & $get_current_process_id() & "-" & port)
        @["--workdir", managed_workdir]
    flags =
      @["--world", absolute_path(world)] & (if ?level: @["--level", level] else: @[]) &
      @["--listen", address, "--minimized"] & workdir_flags &
      # it quits if we die without cleaning up (a crash, kill -9)
      @["--exit-with", $get_current_process_id()]
    log = get_temp_dir() / "enu_managed.log"
  when defined(windows):
    # TODO: Windows managed launch (no /bin/sh; needs output redirection).
    raise ValueError.init("Managed Enu launch is not yet supported on Windows")
  else:
    # Run via the shell with `exec` so the child PID is Enu itself (directly
    # killable) and its noisy stdout/stderr land in a log rather than corrupting
    # our own stdout — which, for the MCP server, is the JSON-RPC channel.
    let cmd =
      "exec " & quote_shell(spec.exe) & " " &
      (spec.args & flags).map(quote_shell).join(" ") & " > " & quote_shell(log) &
      " 2>&1"
    enu_process =
      start_process("/bin/sh", working_dir = spec.workdir, args = ["-c", cmd])
    managed_pid = enu_process.process_id
    if not exit_hook_added:
      # a failing test's `quit 1` exits without reaching `disconnect`
      exit_hook_added = true
      add_exit_proc proc() {.noconv.} =
        if managed_pid > 0:
          discard posix.kill(Pid(managed_pid), SIGTERM)
  # Retry until the launched Enu boots and answers; each attempt is bounded by
  # the client's connect_timeout. A busy machine can take most of a minute to
  # boot it, so give up early only if it exits.
  Enu.client(address = address, id = id).connect
  discard Enu.client.tick_until(
    timeout,
    Enu.client.connected or Enu.client.refusal != "" or not enu_process.running,
  )
  if not Enu.client.connected:
    let refusal = Enu.client.refusal
    Enu.disconnect
    if refusal != "":
      raise SchemaMismatchError.init(refusal)
    raise ValueError.init("Launched Enu but could not connect at " & address)
  address

proc managing*(_: type Enu): bool =
  ## Whether we currently own a launched Enu.
  not enu_process.is_nil
