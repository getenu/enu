# Multiplayer Discovery — finding and joining enu worlds

> Status: **design / plan.** How players find each other and connect, short of
> the full decentralized-identity story. Companion to `durable-persistence.md`
> (stable player identity, `PlayerRecord`) and the long-term git-stored
> contributor-key direction. Grounded in an audit of the current transport
> (`worker.nim`, `client.nim`, `game.nim`, `ui/settings.nim`, ed's
> `subscriptions/core.nim`, and `deps/netty`). Nothing here is built yet; the
> three v1 decisions (keypairs, encryption, relay) are settled — see **Decisions**.

## Goal

Let people connect to each other without hand-typing IP addresses, with a host
approval step, so that once approved a player can reconnect indefinitely (both
parties on the internet), and the host can kick a player, which forces
re-approval. Keep required public infrastructure minimal and cheap. Flag every
security risk so the trust boundary is a conscious choice, not an accident.

This is the short-term bridge to proper enu identity, where a project's git repo
stores contributor public keys and controls world access. v1 is built so its
pieces migrate into that model rather than being thrown away.

## Where things stand today

- **Transport.** `ed` over `netty` (a UDP reliability layer). Whoever passes
  `--listen` is the authority (`is_server = ?listen_address or not
  ?connect_address`, `worker.nim`); everyone else does
  `subscribe(connect_address, mode = PARTIAL_ASYNC)`. Default port `9632`.
- **No discovery.** Connection is a hand-typed `host:port` (settings field,
  `connect_address`, `--connect`, `ENU_CONNECT_ADDRESS`). No LAN beacon, no
  directory.
- **No authn/authz.** netty accepts a connection from *any* source address that
  sends a valid first part. ed's SUBSCRIBE handshake carries only
  `(type_ids, partial, fetch, deep)` — no identity, no token. The authority ACKs
  and immediately pushes objects (`add_subscriber`). There is no host approval
  step anywhere.
- **No transport security.** Plaintext UDP, no encryption, no integrity.
- **NAT.** netty has `punchThrough` (a UDP hole-punch primitive) but no
  rendezvous/STUN, so WAN play today needs manual port-forwarding or a LAN.
- **Identity.** The player is an *ephemeral* `player-{ctx.id}`, regenerated per
  connection; `player_color` is random. A stable player id in `config.json` is
  planned in `durable-persistence.md` but not built. No keypair exists yet.

One fact shapes the whole trust model: **joining runs the host's scripts in your
VM, and the host runs yours** (each thing's script runs in the joiner's worker
VM). Those scripts run *sandboxed* — the Nim VM blocks the classic escapes
(arbitrary file r/w, `staticExec`/`gorge`, `slurp`/`staticRead`, FFI `importc`,
env leaks) and PR #78 closes the remaining bridged-host-proc path-traversal
escapes (`load_level`, `reset_level`, `read_enu_script`, `claim_name`). Once #78
lands the sandbox is relatively solid: a peer can be obnoxious and burn CPU or
storage, but shouldn't be able to escape. So approval is about resource abuse and
nuisance, not host compromise. See **Security**.

## Decisions (settled)

1. **Keypairs now**, not tokens. The reconnect/kick credential is an Ed25519
   identity; the peer proves possession of its private key. Feasible with no new
   heavy dependency — `bearssl` is already in the tree (via the chronos stack)
   and provides Ed25519/X25519/ChaCha20-Poly1305.
2. **Bundle transport encryption** with the identity work: an authenticated
   encrypted channel (X25519 + a Noise-style handshake, e.g. Noise IK) so the
   two peers' static keys authenticate the session and everything after the
   handshake is encrypted and integrity-protected. Gate the invite-link/WAN path
   on this; LAN-only may ship ahead of it if we want an early build.
3. **Punch + relay fallback.** The rendezvous brokers hole-punching and relays
   packets when punch fails (symmetric NAT). Everyone can connect, and peer IPs
   can be hidden behind the relay.

## Identity

A single Ed25519 keypair per install, generated once and stored with the user
config. The public key is the player's durable identity; it backs both the
`durable-persistence.md` `PlayerRecord` (replacing the planned random config id)
and access control here.

- **`authorized_peers`** — the host's list of approved peer public keys (plus a
  display name/color cache). Approve = add a key; kick = remove it and
  unsubscribe. Structured so it can later *become* the git-committed
  `authorized_keys`-style file that the long-term model reads from the repo. No
  throwaway token layer.
- **Reconnect** is unforgeable: on return the peer completes the encrypted
  handshake proving its key; if the key is still in `authorized_peers`, it's let
  straight back in with no prompt. Kicked = key removed, so it lands back at the
  approval prompt (and can be denied) regardless of what address it comes from.

## Discovery paths

### LAN — zero infrastructure

A UDP broadcast/multicast beacon on our port: a host announces
`{room-name, host-pubkey, endpoint}`; joiners render a live list and pick one.
(mDNS/DNS-SD is the "proper" form; a plain broadcast beacon is far less code and
enough for v1.) Net-new — nothing exists for this today.

### Invite links — one small server

STUN alone is insufficient: it only reports your *own* public endpoint and can't
give a joiner a durable way to reach a host whose home IP and NAT mapping churn.
What's needed is a **rendezvous / signaling server**:

- The host registers a stable room id and keeps its UDP mapping warm with
  keepalives (the server always knows the host's current public endpoint).
- The invite link encodes `room-id + host-pubkey` (and grants only *may
  request*, never *pre-approved*; make links expirable/revocable).
- On join, the server reflects both public endpoints and both sides
  `punchThrough` simultaneously; it **relays** if the punch fails.

That one process is registration + STUN reflection + punch broker + relay — a
free-tier VPS. It must only ever reflect/relay to endpoints that have proven
liveness to it (anti-reflection; see Security #5). It never needs to decrypt
traffic: with e2e keys it brokers endpoints and moves opaque bytes.

## Approval gate — before ed's subscribe, not inside it

Today `subscribe` immediately `add_subscriber`s and pushes objects. Rather than
teach ed to hold a "pending" subscription, run a small **join-request
pre-handshake** on the same socket (brokered by the rendezvous for invite links,
direct for LAN) that also carries the Noise handshake. Flow:

1. Joiner opens the encrypted channel, presenting its static pubkey.
2. If the key is in `authorized_peers`, skip to step 4 (silent reconnect).
3. Otherwise the host is prompted (name/color/pubkey); on approve, the key is
   added to `authorized_peers`.
4. Only then does the normal ed `subscribe` proceed over the established channel.

This keeps ed unchanged and localizes the new logic in enu. Kick = drop the key
and `unsubscribe` the peer.

### Configurable per channel

Whether step 2/3 prompt at all is **configurable per discovery channel**, since
the sandbox makes the downside of skipping approval nuisance rather than
compromise (see Security #1). For now this lives in `config.json` as two bools,
both **defaulting to require approval**:

- `lan_require_approval` (default `true`) — gate LAN-discovered joiners.
- `invite_require_approval` (default `true`) — gate invite-link joiners.

They follow the existing `Config`/`UserConfig` pattern (`Option[bool]` on
`UserConfig`, plain `bool` on `Config`, defaulted via `uc.x ||= true`). When a
channel's flag is `false`, a first-time joiner on that channel skips the prompt
and is added to `authorized_peers` directly; already-authorized peers reconnect
silently regardless, and kick still works either way. A settings-panel UI can
come later; config is the v1 surface.

## Rough sequencing

1. **Identity + encrypted channel.** Keypair at rest; Noise handshake wrapping
   the netty connection; `authorized_peers`. Wire the approval prompt and kick.
   Prove it on localhost/LAN first.
2. **LAN discovery.** Broadcast beacon + a join list in the UI. Can ship on top
   of (1) as the first user-visible multiplayer-discovery feature.
3. **Rendezvous + invite links.** Stand up the server (register / reflect /
   punch / relay); generate and consume invite links; keepalives. This is the
   WAN path and depends on (1)'s encryption being in place.

## Security

Ranked. The encryption decision closes most of #2–#4 on the WAN path.

1. **Sandboxed script execution — resource abuse, not escape.** Joining runs the
   host's scripts in your VM and vice-versa, but sandboxed: once PR #78 lands the
   Nim VM plus the bridged-proc path guards block the known escapes (file r/w,
   `staticExec`/`slurp`, FFI, traversal). What remains is a *malicious or careless*
   peer being obnoxious — pegging CPU, filling storage, spamming in-world objects
   (a DoS/nuisance surface, mitigated by rate/size limits, not a host compromise).
   Residual defense-in-depth gap: unrestricted `import` of std modules from
   scripts was left out of #78's scope. Confirmed empirically (`nim test_sandbox`,
   the `tests/worlds/sandbox-probe` level) that this is *not* an escape today —
   the load-bearing boundary is the VM's vmop/FFI gate, not import filtering. A
   script that `import std/syncio; read_file(...)` falls through to `fopen`
   (importc) and the VM aborts uncatchably; `import std/envvars; get_env(k)` is
   evaluated but returns "" for every key (a stub — no real env access even with
   the var set). So dropping a copy of the stdlib into the scripts dir buys
   nothing: the capability lives in native op registration, which copies can't
   reach and the real modules don't have bridged here. Import restriction stays a
   surface-reducer, never the boundary. Honest framing softens from *only people
   you trust* to *approval keeps out nuisances*, but the vmop/FFI gate is the
   load-bearing assumption; re-audit it (and re-run `test_sandbox`) before any
   open/public-server future.
2. **Plaintext transport (mitigated by Decision 2).** Without encryption anyone
   on-path (LAN, ISP, rendezvous operator) can read and modify traffic — inject
   objects/scripts, MITM. Closed by the Noise channel; the risk is real for any
   build that ships before it.
3. **Unauthenticated wire (mitigated by Decision 2).** Guessable connection ids +
   no session key let an on-path or source-spoofing attacker hijack/inject. A
   plaintext approval token would be replayable/stealable — another reason to go
   straight to key-authenticated sessions.
4. **Rendezvous as trust anchor / metadata sink.** It learns who-connects-to-whom
   and both IPs. e2e keys stop it injecting; it still sees metadata. Keep it dumb.
5. **UDP amplification / punch-reflection DDoS.** An unauthenticated listener is a
   reflection vector, and a naive rendezvous that punches at an arbitrary address
   becomes a third-party DDoS tool. Only reflect/relay to endpoints that proved
   liveness to the server; rate-limit.
6. **Peer IP exposure.** Direct P2P reveals both home IPs to each other
   (deanonymization/harassment, more so with kids). The relay hides it at a
   bandwidth cost — a conscious per-connection tradeoff.
7. **Invite links are bearer secrets.** They leak via chat/screenshots. Grant
   only *may request* (approval still gates the join); make them expirable and
   revocable.
8. **Credential at rest.** A stolen private key or an edited `authorized_peers`
   file = silent access. Kick keys on pubkey, not address, so a kicked peer can't
   walk back in from a new IP.
9. **Resource exhaustion.** A partial-replica joiner can pull large worlds; a
   malicious one can pull a lot. Rate/size-limit server-side.

None of these block a *trusted-friends* v1 — they're the informed-decision
surface. With the sandbox closing #1 down to resource abuse, #2/#3 (plaintext,
unauthenticated wire) become the practical blockers for the invite-link/WAN path,
which is why encryption is sequenced alongside identity rather than after.
