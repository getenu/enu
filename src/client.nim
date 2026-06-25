## Client-side convenience layer for native apps that drive a running Enu
## over `ed` (the demos under `bin/`, the MCP server). `Enu` is a marker type
## whose "class methods" wrap the boilerplate of standing up an `EdClient` and
## reaching into its context, so an app reads `Enu.client` / `Enu.units`
## instead of spelling out the context plumbing.
##
## This is purely an app-facing helper — regular Enu doesn't use it.

import std/[os, osproc, net, strutils, sequtils]
import pkg/ed
import core, models/units

export ed, core, units

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

proc units*(_: type Enu): EdSeq[Unit] =
  ## The level's top-level units, via this thread's client.
  EdSeq[Unit](enu_client.ctx["root_units"])

proc find_unit*(_: type Enu, id: string): Unit =
  ## The root unit with this `id`, or nil if there's no match.
  for unit in Enu.units:
    if unit.id == id:
      return unit

proc ask*(unit: Unit, q: UnitQuery, timeout = 30.seconds): UnitQuery =
  ## File query `q` against `unit` and tick until Enu answers (or `timeout`).
  let slot = unit.query(q)
  if Enu.client.tick_until(timeout, slot.value.state == DONE):
    return slot.value
  unit.query = UnitQuery(state: DONE)
  UnitQuery(state: DONE, error: "Error: Enu did not respond within " & $timeout)

proc answer*(q: UnitQuery): string =
  ## A query's result, or its error message.
  if q.error != "": q.error else: q.result

proc eval*(unit: Unit, code: string, top_level = false): string =
  ## Run Nim `code` in `unit`'s scripting context; return the value or error.
  answer unit.ask(UnitQuery(kind: EVAL, code: code, top_level: top_level))

# --- Managed Enu instances -------------------------------------------------
# Launch and own an Enu process, rather than connecting to one the user is
# running. Backs the MCP server's launch_enu/kill_enu tools and the MCP
# integration tests: an agent (or a test) can stand up a private Enu on a
# random port and tear it down again.

var enu_process {.threadvar.}: Process
  ## The Enu we launched, if any. Only this process may be `Enu.kill`ed — we
  ## never touch an Enu the user is running.

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
  if not enu_process.is_nil:
    enu_process.terminate()
    discard enu_process.wait_for_exit(timeout = 3000)
    if enu_process.running:
      enu_process.kill()
      discard enu_process.wait_for_exit()
    enu_process.close()
    enu_process = nil

proc disconnect*(_: type Enu) =
  ## Drop the client connection. If we launched the Enu (via launch_and_connect)
  ## terminate it too — we never kill an Enu the user is running. Safe to call
  ## when nothing is connected.
  terminate_managed()
  if not enu_client.is_nil:
    if not enu_client.ctx.is_nil:
      enu_client.ctx.close
    enu_client = nil

proc connect*(_: type Enu, address = "", id = ""): bool {.discardable.} =
  ## Attach to a running Enu at `address` (else $ENU_CONNECT_ADDRESS, else
  ## "127.0.0.1" on ed's default port). Drops any current connection / managed
  ## process first; does NOT launch anything. Returns whether it connected. The
  ## target Enu must be listening (started with --listen); the client's
  ## connect_timeout bounds the attempt so an absent peer fails fast.
  Enu.disconnect
  let resolved =
    if address != "": address else: get_env("ENU_CONNECT_ADDRESS", "127.0.0.1")
  Enu.client(address = resolved, id = id).connect
  result = Enu.client.connected
  if not result:
    Enu.disconnect

proc launch_and_connect*(
    _: type Enu,
    level_dir: string,
    id = "",
    timeout = 30.seconds,
    temp_workdir = false,
): string =
  ## Launch a private Enu opening `level_dir` on a random free port (listening,
  ## minimized), connect to it, and return its "host:port" address. The instance
  ## is ours: `disconnect` (or process exit) kills it. `level_dir` is required.
  ## `temp_workdir` runs against a throwaway copy of the level (for tests) so the
  ## source is never modified.
  if level_dir == "":
    raise ValueError.init("launch_and_connect requires a level_dir")
  Enu.disconnect
  let
    address = "127.0.0.1:" & $free_port()
    spec = launch_spec()
    flags =
      @["--level-dir", level_dir, "--listen", address, "--minimized"] &
      (if temp_workdir: @["--temp-workdir"] else: @[])
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
  # Retry until the launched Enu boots and answers; each attempt is bounded by
  # the client's connect_timeout.
  Enu.client(address = address, id = id).connect
  if not Enu.client.tick_until(timeout, Enu.client.connected):
    Enu.disconnect
    raise ValueError.init("Launched Enu but could not connect at " & address)
  address

proc managing*(_: type Enu): bool =
  ## Whether we currently own a launched Enu.
  not enu_process.is_nil
