## Helpers for an external agent that drives Enu over an `EdContext` — the
## MCP server is the first such agent. Nothing here is MCP-specific: spawn
## an agent bot, hydrate a partially-replicated object, ask any unit a
## cross-context query, and animate a unit's transform by ticking the shared
## context each frame.
##
## This module is compiled into the agent process (e.g. `bin/enu`), not
## the Enu dylib.

import std/[os, math, monotimes, times]
import core
import models/[bots, units, players, colors]
import ed

const
  FRAME_MS = 33
  FRAME_SEC = FRAME_MS.float / 1000.0
  MOVE_SPEED = 50.0       ## units / second
  ANGULAR_SPEED = 180.0   ## degrees / second
  TELEPORT_DIST = 500.0   ## skip the glide past this distance

proc root_units*(ctx: EdContext): EdSeq[Unit] =
  EdSeq[Unit](ctx["root_units"])

proc find_unit*(ctx: EdContext, id: string): Unit =
  for u in ctx.root_units:
    if u.id == id:
      return u

proc hydrate*[T: EdRef](ctx: EdContext, obj: T) =
  ## Fill in an object that arrived over a partial replica. The object itself
  ## synced inline, but its container fields can be unregistered stubs — their
  ## CREATEs were filtered before this session expressed interest. Deep-fetch
  ## the object's owned closure, wait (bounded) for it to land, then re-link
  ## the fields to the real containers. On a full replica everything is
  ## already registered, so this passes through instantly as a no-op.
  ctx.fetch(obj.id, deep = true)
  let deadline = get_mono_time() + init_duration(seconds = 2)
  var pending = true
  while pending and get_mono_time() < deadline:
    ctx.tick
    pending = false
    for field in obj[].fields:
      when field is Ed:
        if ?field and field.id notin ctx:
          pending = true
    if pending:
      sleep FRAME_MS
  for field in obj[].fields:
    when field is Ed:
      if ?field and field.id in ctx:
        field = type(field)(ctx[field.id])

proc spawn_bot*(
    ctx: EdContext, id: string, color: Color,
    at = Transform.init(vec3(0, 1, 0)), visible = true,
): Bot =
  ## Create a bot owned by this context, flagged AGENT so it survives level
  ## reloads, isn't persisted with the level, and is reaped when this context
  ## disconnects. `visible = false` creates it hidden (a one-shot CLI call
  ## doesn't need an in-world avatar flashing in and out) — screenshots are
  ## unaffected, they render from a dedicated camera, not the bot node.
  result = Bot.init(id = id)
  result.color = color
  result.global_flags += AGENT
  if not visible:
    result.global_flags -= VISIBLE
  ctx.root_units.add result
  result.transform = at

proc ensure_agent_bot*(
    ctx: EdContext, id: string, color: Color,
    at = Transform.init(vec3(0, 1, 0)), visible = true,
): Bot =
  ## Find this agent's bot by id (a reconnect after an Enu restart), or spawn
  ## a fresh one.
  let existing = ctx.find_unit(id)
  if not existing.is_nil and existing of Bot:
    result = Bot(existing)
    ctx.hydrate(result)
  else:
    result = ctx.spawn_bot(id, color, at, visible)

proc rotation*(unit: Unit): float =
  ## Yaw in degrees. Players track yaw directly; everyone else derives it
  ## from the transform basis.
  if unit of Player: Player(unit).rotation
  else: rad_to_deg(unit.transform.basis.get_euler().y)

proc move_to*(unit: Unit, pos: Vector3, yaw_deg: float) =
  ## Set a unit's position and yaw (no pitch).
  unit.transform = Transform.init(pos, yaw_deg)
  if unit of Player:
    Player(unit).rotation = yaw_deg

proc aim*(unit: Unit, pos: Vector3, yaw_rad, pitch_rad: float) =
  ## Position a unit and orient it with yaw + downward pitch — used to aim a
  ## camera at a target. Builds the look basis directly (forward / right /
  ## up) so off-axis angles don't roll the horizon.
  let
    cy = cos(yaw_rad)
    sy = sin(yaw_rad)
    cp = cos(pitch_rad)
    sp = sin(pitch_rad)
    forward = vec3(float32(sy * cp), float32(-sp), float32(-cy * cp))
    right = vec3(float32(cy), 0'f32, float32(sy))
    up = right.cross(forward)
  var t = Transform()
  t.basis = init_basis(
    vec3(right.x, up.x, -forward.x),
    vec3(right.y, up.y, -forward.y),
    vec3(right.z, up.z, -forward.z),
  )
  t.origin = pos
  unit.transform = t
  if unit of Player:
    Player(unit).rotation = rad_to_deg(yaw_rad)

template animate*(ctx: EdContext, seconds: float, body: untyped) =
  ## Run `body` once per ~33ms frame for `seconds`, ticking `ctx` each frame
  ## so transform changes sync. A float `t` in 0..1 is injected (1.0 on the
  ## final frame). A final tick flushes the last frame.
  block:
    let total = max(seconds, FRAME_SEC)
    var elapsed = 0.0
    while true:
      ctx.tick
      elapsed += FRAME_SEC
      let t {.inject.} = float min(elapsed / total, 1.0)
      body
      if t >= 1.0:
        ctx.tick
        break
      sleep FRAME_MS

proc glide*(
    unit: Unit, ctx: EdContext, target: Vector3, rotation = 0.0,
    speed = MOVE_SPEED, instant = false,
) =
  ## Smoothly move `unit` to `target` (and rotate to `rotation` degrees),
  ## ticking `ctx` each frame. Teleports instantly past `TELEPORT_DIST`, or
  ## always with `instant` (one-shot CLI calls just want the end state).
  let
    start = unit.transform.origin
    start_rot = unit.rotation
  var angle_diff = rotation - start_rot
  angle_diff -= round(angle_diff / 360.0) * 360.0
  let
    dist = start.distance_to(target)
    seconds = max(dist / speed, abs(angle_diff) / ANGULAR_SPEED)
  if instant or dist >= TELEPORT_DIST or seconds < FRAME_SEC:
    unit.move_to(target, rotation)
    ctx.tick
    return
  ctx.animate(seconds):
    if not ?unit.transform_value:
      break
    unit.move_to(start + (target - start) * t, start_rot + angle_diff * t)

proc frame*(
    target: Vector3, distance, height, angle: float
): tuple[pos: Vector3, yaw_rad, pitch_rad: float] =
  ## Compute a camera pose that frames `target` from `distance` away,
  ## `height` above, swung `angle` degrees around it (0 = south).
  let
    angle_rad = deg_to_rad(angle)
    pos = vec3(
      target.x + distance * sin(angle_rad), target.y + height,
      target.z + distance * cos(angle_rad),
    )
    dir = target - pos
    horiz = sqrt(dir.x * dir.x + dir.z * dir.z)
  result = (pos, arctan2(float(dir.x), -float(dir.z)),
            -arctan2(float(dir.y), float(horiz)))

proc look_at*(
    unit: Unit, ctx: EdContext, target: Vector3,
    distance = 30.0, height = 8.0, angle = 0.0, instant = false,
) =
  ## Glide `unit` to a framing pose for `target`, landing aimed at it
  ## (including downward pitch). Ticks `ctx` a few extra times so the final
  ## transform reaches the renderer before a screenshot.
  let (pos, yaw_rad, pitch_rad) = frame(target, distance, height, angle)
  unit.glide(ctx, pos, rad_to_deg(yaw_rad), instant = instant)
  unit.aim(pos, yaw_rad, pitch_rad)
  for _ in 0 .. 2:
    ctx.tick
    sleep 20

proc ask*(
    unit: Unit, ctx: EdContext, q: UnitQuery,
    timeout = init_duration(seconds = 30),
): UnitQuery =
  ## Run a query against `unit` from this context: set the unit's query slot,
  ## tick `ctx` until whichever context answers it reports QUERY_DONE, and
  ## return the completed query. On timeout, clears the slot and returns an
  ## error result.
  var pending = q
  pending.state = QUERY_PENDING
  unit.query = pending
  let start = get_mono_time()
  while true:
    ctx.tick
    let v = unit.query
    if v.state == QUERY_DONE:
      return v
    if not ctx.connected:
      # Peer went away mid-query (e.g. Enu restarted). tick reaps the dead
      # connection within netty's timeout; bail so the caller can reconnect.
      return UnitQuery(state: QUERY_DONE, error: "Error: connection lost")
    if get_mono_time() - start > timeout:
      unit.query = UnitQuery(state: QUERY_DONE)
      return UnitQuery(
        state: QUERY_DONE,
        error: "Error: Enu did not respond within " & $timeout,
      )
    sleep 10
