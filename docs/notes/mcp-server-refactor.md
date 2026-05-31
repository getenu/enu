# MCP server refactor — plan

## Problem

`enu_mcp.nim` is bloated with connection-keeping logic (ping, reconnect,
animation interpolation) that doesn't belong in an MCP server. The root
cause of the disconnect fragility: nimcp's `serve` blocks on
`stdin.readLine()`, so the Ed context is **only ticked inside tool
handlers**. Between tool calls (often minutes), it never ticks — netty's
keepalives never fire, dead connections are never reaped, and
`subscribers.len` goes stale. The bespoke ping exists purely to detect a
death that regular ticking would prevent in the first place.

## Core insight

Tick the context during idle. Then:

- Netty keepalives flow on their own → an idle connection no longer dies.
- `tick` already calls `tick_keepalives` *and* reaps dead connections, so
  `connected = subscribers.len > 0` becomes a reliable, generic disconnect
  signal — no app-level ping required.
- Reconnect becomes a true fallback for an actual Enu restart, detected
  within netty's ~10s keepalive window (plus an immediate force-reconnect
  after any tool-call timeout).

This deletes most of the MCP server's hand-rolled machinery and pushes the
remaining generic pieces down into Ed (connection) and Enu (agent bot +
animation).

## What goes where

### Ed (`deps/ed`) — generic connection client

New `src/ed/client.nim`:

```nim
proc connected*(ctx: EdContext): bool = ctx.subscribers.len > 0

template every*(ctx: EdContext, interval: Duration, body: untyped) =
  ## Tick `ctx` then run `body` every `interval` until `body` breaks.
  ## One primitive for: idle keepalive, change polling, 30fps animation.

type EdClient* = ref object
  id*, address*: string
  ctx*: EdContext
  chan_size*: int
  on_connect*: proc() {.gcsafe.}   ## (re)create app objects after connect

proc connect*(c: EdClient)           ## init ctx (stable id) + subscribe + on_connect
proc connected*(c: EdClient): bool
proc ensure_connected*(c: EdClient)  ## reconnect (recreate ctx+objects, same id) if down
proc tick*(c: EdClient)              ## ctx.tick; reconnect if dropped
```

Reconnect recreates the context with the **same** stable id and reruns
`on_connect` — the existing approach, just packaged generically. No MCP
knowledge in Ed.

### Enu (`src`) — agent bot + animation

`models/bots.nim`:

```nim
proc ensure_agent_bot*(ctx: EdContext, id: string, color: Color): Bot
  ## find-or-create the AGENT bot (folds in today's ensure_bot)

proc query*(bot: Bot, ctx: EdContext, q: McpQuery,
            timeout = 30.seconds): McpQuery
  ## set bot.mcp_query, tick ctx until MCP_DONE or timeout, return result
```

`models/units.nim` (animation, composes `ctx.every`):

```nim
template animate*(unit: Unit, ctx: EdContext, seconds: float, body: untyped)
  ## run body each ~33ms frame for `seconds`, ticking ctx; `t` (0..1) injected

proc glide*(unit, ctx, target, rotation, speed = 50, ...)   ## smooth move
proc look_at*(unit, ctx, target, distance, height, angle)   ## framing move
```

These are reusable by any external Ed client driving an Enu unit — not MCP
specific. The three current interpolation loops collapse into `glide` /
`look_at` calls.

### nimcp (`deps/nimcp`) — non-blocking serve

Add an `idle` callback to stdio `serve`. A dedicated stdin reader thread
pushes lines onto a `Channel[string]` (the only thing off the main thread —
it never touches Ed). The main loop drains the channel (handling requests on
the main thread, satisfying the "tick in the same thread" requirement),
calls `idle()` between requests, sleeps briefly. Generic MCP feature
("serve with periodic background work"), no Enu knowledge.

### `bin/enu_mcp.nim` — thin

```nim
let client = EdClient(id: "enu_mcp-" & generate_id(), address: connect_addr)
client.on_connect = proc() = bot = ensure_agent_bot(client.ctx, ...)

proc run_tool(...): string =
  client.ensure_connected
  bot.query(client.ctx, McpQuery(...)).result_or_error

let server = mcp_server("enu", "1.0.0"):
  mcp_tool: ...        # tool bodies call run_tool / unit.glide / unit.look_at

new_stdio_transport().serve(server, idle = proc() = client.tick)
```

Stable ctx id + bot-id-derives-from-ctx-id is already how it works today;
kept. `last_bot_transform` (bot lands where it was after reconnect) folds
into `on_connect`.

## Phases (each gated on its own tests)

0. **Baseline** — `nim build` + `nim test` green; launch Enu in background
   (`ENU_LISTEN_ADDRESS=127.0.0.1`); run `bin/enu_mcp_reconnect_test.nim` to
   capture current behavior.
1. **Ed client** — add `client.nim`; `cd deps/ed && nimble test`.
2. **nimcp idle serve** — reader-thread serve; `cd deps/nimcp && nimble test`.
3. **Enu helpers** — `ensure_agent_bot`/`query`/`animate`/`glide`/`look_at`;
   `nim build` + `nim test`.
4. **Rewrite enu_mcp.nim thin** — rebuild dylib, relaunch Enu, run both
   `enu_mcp_reconnect_test` and `enu_mcp_test`.
5. **Restart-survival** — scripted: with a live session, kill+relaunch Enu,
   confirm the session recovers on the next tool call.
6. **Cleanup + commit** — remove any debug logging; commit ed, nimcp, enu
   in their own repos with focused messages.

## Verification constraint

All overnight verification is via the test harnesses + background Enu — no
interactive MCP reconnect (that happens in the morning). The reconnect test
is the key gate: with idle-ticking, the 15s-idle case should stay connected
the whole time (keepalives prevent the timeout) rather than reconnecting,
which is the ideal outcome.

## Decisions / non-goals

- **Drop the bespoke app-level ping.** Rely on idle-tick + `subscribers.len`
  + force-reconnect-after-timeout. If the reconnect test regresses, restore
  a minimal liveness confirmation — but I expect it to improve.
- **Keep the `McpQuery` name.** Renaming to a generic `AgentQuery` is a
  tempting cleanup but a cross-cutting rename (types/bots/host_bridge/
  bot_node) with no functional gain; out of scope.
- **Don't touch the worker-side mcp handler** (`bots.worker_thread_joined`).
  The wire protocol (McpQuery flatty) is unchanged, so an old Enu dylib
  still interoperates; I rebuild+relaunch anyway before integration tests.
- **#63 (`.new(rotation=)` bug)** stays separate — untouched.

## Results (overnight run)

Done and verified via the test harnesses (no interactive MCP):

- **ed** `EdClient` + `connected` + `every` (commit in deps/ed). Threaded
  round-trip test passes; full `nimble test` green.
- **nimcp** stdio `serve` idle callback (commit) + two stdout-hygiene fixes
  (commit): the non-chronicles logging fallback defaulted to a stdout
  handler, and `handleToolsList` had a debug `echo` — both corrupted the
  stdio JSON-RPC stream. `nimble test` green (14 files).
- **enu** `src/agent.nim` (agent bot + query + animate/glide/look_at) and a
  thin `bin/enu_mcp.nim` rewrite (commit). Plus restart-robustness:
  `query` exits early when the connection drops, and `run_tool`
  reconnects+retries once on a dropped query.
- **Integration**: `enu_mcp_test` 8/8 pass (it caught the two stdout bugs);
  `enu_mcp_reconnect_test` 3/3; restart-survival probe passes — a kept-open
  session evaluated `40+2→42`, Enu was killed and relaunched, then the same
  session evaluated `1+2→3` after auto-recovery.

### Findings for the morning (not fixed — out of scope)

- **nimcp ignores Nim param defaults**: a tool call must include *every*
  declared parameter in its JSON args, or it errors `key not found: <param>`.
  Claude's client sends all args per the schema, so eval/etc. work in
  practice, but "optional" params aren't truly optional for other clients.
- **`enu_mcp_reconnect_test` eval assertions were weak** (`"1" in r1`): they
  matched the `requestId:"1"` inside an *error* response, so they verified a
  round-trip but not eval execution. The set_position case (sends all args)
  did verify the move path. Strengthened to send full args.
- The idle-tick fix means the 15s-idle reconnect case now stays connected
  the whole time (keepalives prevent the timeout) rather than dropping and
  reconnecting — the intended outcome.
