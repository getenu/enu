## Client-side convenience layer for native apps that drive a running Enu
## over `ed` (the demos under `bin/`, the MCP server). `Enu` is a marker type
## whose "class methods" wrap the boilerplate of standing up an `EdClient` and
## reaching into its context, so an app reads `Enu.client` / `Enu.units`
## instead of spelling out the context plumbing.
##
## This is purely an app-facing helper — regular Enu doesn't use it.

import std/os
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
