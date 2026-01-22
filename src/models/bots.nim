import std/[math, sugar, monotimes, base64]
import godotapi/spatial
import core, models/[states, units, colors]
include "bot_code_template.nim.nimf"

method code_template*(self: Bot, imports: string): string =
  result = bot_code_template(
    read_file(self.script_ctx.script).encode(safe = true),
    self.script_ctx.script,
    imports,
  )

method on_begin_move*(
    self: Bot, direction: Vector3, steps: float, moving_mode: int
): Callback =
  # move_mode param is ignored
  var duration = 0.0
  let
    moving = -self.transform.basis.z
    finish = self.transform.origin + moving * steps
    finish_time = 1.0 / self.speed * steps
    target_velocity = moving * self.speed

  # Set velocity once at start
  self.velocity = target_velocity

  result = proc(delta: float, _: MonoTime): TaskStates =
    duration += delta
    if duration >= finish_time:
      self.velocity = vec3()
      self.transform_value.origin = finish.snapped(vec3(0.1, 0.1, 0.1))
      return DONE
    else:
      return RUNNING

method on_begin_turn*(
    self: Bot, axis: Vector3, degrees: float, lean: bool, move_mode: int
): Callback =
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
    id = "bot_" & generate_id(),
    transform = Transform.init,
    clone_of: Bot = nil,
    global = true,
    parent: Unit = nil,
): Bot =
  var self = Bot(
    id: id,
    start_transform: transform,
    animation_value: ed("auto"),
    speed: 1.0,
    clone_of: clone_of,
    start_color: ACTION_COLORS[BLACK],
    parent: parent,
  )

  self.init_unit

  if global:
    self.global_flags += GLOBAL
  result = self

method clone*(self: Bot, clone_to: Unit, id: string): Unit =
  var transform = clone_to.transform
  result =
    Bot.init(id = id, transform = transform, clone_of = self, parent = clone_to)

method on_collision*(self: Unit, partner: Model, normal: Vector3) =
  self.collisions.add (partner.id, normal)

method off_collision*(self: Unit, partner: Model) =
  for collision in self.collisions.dup:
    if collision.id == partner.id:
      self.collisions -= collision

method worker_thread_joined*(self: Bot) =
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
