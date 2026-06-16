import std/[math, sugar, monotimes, os]
import godotapi/spatial
import core, models/[states, units, colors]
export units
include "bot_code_template.nim.nimf"

method code_template*(self: Bot, imports: string): string =
  result = bot_code_template(
    "../scripts/" & self.script_ctx.script.extractFilename(), imports
  )

method on_begin_move*(
    self: Bot, direction: Vector3, steps: float, moving_mode: int
): Callback =
  if moving_mode == 3:
    let offset = self.anchor_value.basis.xform(direction) * steps
    self.anchor_value.origin = self.anchor_value.origin + offset
    return
  # Move mode param is ignored
  var duration = 0.0
  let
    moving = -self.transform.basis.z
    finish = self.transform.origin + moving * steps
    finish_time = 1.0 / self.speed * steps

  result = proc(delta: float, _: MonoTime): TaskStates =
    duration += delta
    if duration >= finish_time:
      self.velocity_value.touch(vec3())
      self.transform_value.origin = finish.snapped(vec3(0.1, 0.1, 0.1))
      return DONE
    else:
      self.velocity_value.touch(moving * self.speed)
      return RUNNING

method on_begin_turn*(
    self: Bot, axis: Vector3, degrees: float, lean: bool, move_mode: int
): Callback =
  if move_mode == 3:
    let world_axis = self.anchor_value.basis.xform(axis)
    self.anchor_value.basis =
      self.anchor_value.basis.rotated(world_axis, deg_to_rad(degrees))
        .orthonormalized
    return
  # move mode param is ignored
  let degrees = degrees * -axis.x
  var duration = 0.0
  let
    start_basis = self.transform.basis
    final_basis = start_basis.rotated(UP, deg_to_rad(degrees))
  result = proc(delta: float, _: MonoTime): TaskStates =
    duration += delta
    if duration <= 1.0 / self.speed:
      # Use start_basis for incremental rotation to avoid compounding rotations
      self.transform_value.basis =
        start_basis.rotated(UP, deg_to_rad(degrees * duration * self.speed))
      RUNNING
    else:
      self.transform_value.basis = final_basis
      DONE

proc bot_at*(state: GameState, position: Vector3): Bot =
  for unit in state.units:
    if unit of Bot and unit.transform.origin == position:
      return Bot(unit)

proc reset_state*(self: Bot) =
  self.transform = self.start_transform

method reset*(self: Bot) =
  self.reset_state
  self.speed = 5
  self.color = self.start_color
  self.animation_value.touch "auto"
  self.global_flags += VISIBLE
  self.velocity = vec3()
  self.units.clear()

method destroy*(self: Bot) =
  self.destroy_impl

proc init*(
    _: type Bot,
    id = "bot_" & generate_id() & "-" & Ed.thread_ctx.id,
    transform = Transform.init,
    clone_of: Bot = nil,
    global = true,
    parent: Unit = nil,
): Bot =
  ## The level-bot initializer enu uses internally (placed, loaded, cloned):
  ## the bot belongs to the level and persists with it. Demos and external
  ## agents want a session-scoped bot instead — see the `(x, y, z, save = ...)`
  ## overload below, which sets EPHEMERAL.
  id.own:
    var self = Bot(
      id: id,
      start_transform: transform,
      animation_value: ed("auto"),
      clone_of: clone_of,
      start_color: ACTION_COLORS[BLACK],
      parent: parent,
    )

    self.init_unit
    self.speed = 1.0 # bots walk by default (init_unit defaults speed to 0/ASAP)

    if global:
      self.global_flags += GLOBAL
    result = self

proc init*(
    _: type Bot,
    x, y, z: float,
    save = false,
    color = ACTION_COLORS[BLACK],
    id = "bot_" & generate_id() & "-" & Ed.thread_ctx.id,
): Bot =
  ## A bot at (x, y, z) for demos and external agents. EPHEMERAL by default —
  ## session-scoped: it survives reloads, is skipped by persistence, and is
  ## reaped when the session ends. Pass `save = true` to keep it in the level.
  result = Bot.init(id = id, transform = Transform.init(vec3(x, y, z)))
  result.color = color
  if not save:
    result.global_flags += EPHEMERAL

method clone*(self: Bot, clone_to: Unit, id: string): Unit =
  var transform = clone_to.transform
  result =
    Bot.init(
      id = id,
      transform = transform,
      clone_of = self,
      parent = clone_to,
    )

method on_collision*(self: Unit, partner: Model, normal: Vector3) =
  self.collisions.add (partner.id, normal)

method off_collision*(self: Unit, partner: Model) =
  for collision in self.collisions.dup:
    if collision.id == partner.id:
      self.collisions -= collision

method worker_thread_joined*(self: Bot, worker: Worker) =
  state.local_flags.watch:
    debug "state flag changed",
      zid,
      changes = change.changes,
      item = change.item,
      unit = self.id,
      ed_id = self.local_flags.id

    if HOVER in self.local_flags:
      if PRIMARY_DOWN.added and state.tool == CODE_MODE:
        let root = self.find_root(true)
        state.open_unit = root
      if SECONDARY_DOWN.added and state.tool == PLACE_BOT:
        # :(
        for unit in self.units:
          if unit of Sign:
            var sign = Sign(unit)
            if sign.owner == self:
              sign.owner = nil

        if self.parent.is_nil:
          state.units -= self
        else:
          self.parent.units -= self

  self.local_flags.watch:
    debug "self flag changed",
      zid,
      changes = change.changes,
      item = change.item,
      unit = self.id,
      ed_id = self.local_flags.id

    if HOVER.added:
      state.push_flag RETICLE_VISIBLE
      if state.tool in {CODE_MODE, PLACE_BOT}:
        let root = self.find_root(true)
        root.walk_tree proc(unit: Unit) =
          unit.local_flags += HIGHLIGHT
    elif HOVER.removed:
      let root = self.find_root(true)
      root.walk_tree proc(unit: Unit) =
        unit.local_flags -= HIGHLIGHT
      state.pop_flag RETICLE_VISIBLE

  if EPHEMERAL in self.global_flags and SERVER in state.local_flags:
    self.query_value.changes(false):
      var q = change.item
      if added:
        case q.state
        of PENDING:
          info "unit query received by worker, running file update",
            kind = $q.kind, id = self.id
          worker.update_files_proc()
          q.state = READY
          self.query = q
        of READY:
          case q.kind
          of CONSOLE:
            q.result = state.console.log.value.join("\n")
            q.state = DONE
            info "console query responding", kind = q.kind, id = self.id
            self.query = q
          of CLEAR_CONSOLE:
            state.console.log.clear()
            q.state = DONE
            self.query = q
          of EVAL:
            let (res, err) =
              worker.eval_proc(q.code, q.top_level, q.unit_id)
            q.result = res
            q.error = err
            q.state = DONE
            info "eval query responding",
              code = q.code, error = q.error, id = self.id
            self.query = q
          of LEVEL_DIR:
            q.result = state.config.level_dir
            q.state = DONE
            info "level query responding", kind = q.kind, id = self.id
            self.query = q
          of PING:
            q.state = DONE
            self.query = q
          of SCREENSHOT:
            # Needs the renderer; answered by the unit's node on the main
            # thread (see bot_node.nim).
            discard
          of BLANK:
            discard
        of IDLE, DONE:
          discard

    # Catch-up: if the asker wrote a query *before* the subscription above
    # was registered (typical when the bot is brand new), `changes` never
    # fires for it. Nudge so the handler picks it up.
    let pending = self.query
    if pending.state == PENDING:
      var q = pending
      worker.update_files_proc()
      q.state = READY
      self.query = q
