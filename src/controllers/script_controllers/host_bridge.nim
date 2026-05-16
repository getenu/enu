import std/[os, macros, math, asyncfutures, hashes, times]
import locks except Lock
import pkg/godot except print
import pkg/compiler/vm except get_int
from pkg/compiler/vm {.all.} import stack_trace_aux
import pkg/compiler/ast except new_node
import pkg/compiler/[vmdef, renderer, msgs]
import pkg/metrics

import godotapi/[spatial, ray_cast]
import
  core, models/[states, bots, builds, units, colors, signs, serializers, voxels]
import libs/[interpreters, eval]
import shared/errors

import ./[vars, scripting]
include ./host_bridge_utils

# Program start time for now_seconds() function
let program_start_time = get_mono_time()

proc now_seconds(): float =
  ## Returns seconds since program start as a float.
  let elapsed = get_mono_time() - program_start_time
  elapsed.inNanoseconds.float / 1_000_000_000.0

proc get_last_error(self: Worker): ErrorData =
  result = self.last_exception.from_exception
  self.last_exception = nil

proc map_unit(self: Worker, unit: Unit, pnode: PNode) =
  debug "mapping pnode ", hash = pnode.hash, unit = unit.id
  self.unit_map[pnode] = unit
  self.node_map[unit] = pnode

proc unmap_unit*(self: Worker, unit: Unit) =
  if unit in self.node_map:
    debug "unmapping node ", hash = self.node_map[unit].hash, unit = unit.id
    self.unit_map.del self.node_map[unit]
    self.node_map.del unit

proc write_stack_trace(self: Worker) =
  private_access ScriptCtx

  let ctx = self.active_unit.script_ctx
  {.gcsafe.}:
    msg_writeln(
      ctx.ctx.config, "stack trace: (most recent call last)", {msg_no_unit_sep}
    )

    stack_trace_aux(ctx.ctx, ctx.tos, ctx.pc)

proc get_unit(self: Worker, a: VmArgs, pos: int): Unit {.gcsafe.} =
  let pnode = a.get_node(pos)
  if pnode.kind != nkNilLit:
    {.gcsafe.}:
      result = self.unit_map[pnode]

proc get_bot(self: Worker, a: VmArgs, pos: int): Bot =
  let unit = self.get_unit(a, pos)
  assert not unit.is_nil and unit of Bot
  Bot(unit)

proc get_build(self: Worker, a: VmArgs, pos: int): Build =
  let unit = self.get_unit(a, pos)
  assert not unit.is_nil and unit of Build
  Build(unit)

proc get_sign(self: Worker, a: VmArgs, pos: int): Sign =
  let pnode = a.get_node(pos)
  if pnode.kind != nkNilLit:
    let unit = self.get_unit(a, pos)
    assert not unit.is_nil and unit of Sign
    result = Sign(unit)

proc to_node(self: Worker, unit: Unit): PNode =
  if ?unit:
    if unit notin self.node_map:
      fail \"unit `{unit.id}` not in node_map"
    self.node_map[unit]
  else:
    ast.new_node(nkNilLit)

proc to_node[T: Unit](self: Worker, units: seq[T]): PNode =
  var node = ast.new_node(nkBracketExpr)
  for unit in units:
    if ?unit:
      node.add self.to_node(unit)
    else:
      node.add ast.new_node(nk_nil_lit)
  result = node

# Common bindings

proc press_action(self: Worker, name: string) =
  state.queued_action = name

proc register_template_node(self: Worker, pnode: PNode, name: string) =
  self.template_node_map[name] = pnode

proc register_active(self: Worker, pnode: PNode) =
  assert not self.active_unit.is_nil
  self.map_unit(self.active_unit, pnode)

proc new_instance(self: Worker, src: Unit, dest: PNode) =
  let id =
    src.id & "_" & self.active_unit.id & "_instance_" &
    $(self.active_unit.units.len + 1)

  var clone = src.clone(self.active_unit, id)
  assert not clone.is_nil
  clone.script_ctx = ScriptCtx.init(
    owner = clone, clone_of = src, interpreter = self.interpreter
  )

  self.map_unit(clone, dest)

  debug "adding to active unit",
    unit = clone.id, active_unit = self.active_unit.id

  self.active_unit.units.add(clone)

proc exec_instance(self: Worker, unit: Unit) =
  let active = self.active_unit
  let ctx = unit.script_ctx
  self.active_unit = unit
  defer:
    self.active_unit = active
  ctx.timeout_at = get_mono_time() + script_timeout
  inc rawExecute_depth
  defer:
    dec rawExecute_depth
  ctx.running = ctx.call_proc("run_script", self.node_map[unit], true).paused

proc active_unit(self: Worker): Unit =
  self.active_unit

proc wake(self: Unit) =
  self.script_ctx.timer = get_mono_time()

proc pause_script(self: Worker) =
  self.active_unit.global_flags -= SCRIPT_INITIALIZING
  self.active_unit.script_ctx.pause()

proc keep_alive(ctx: ScriptCtx) =
  ## Reset the script timeout. For long non-yielding loops (eg. spatial
  ## queries from eval) that have legitimate work to do but no reason to
  ## yield. Call periodically — the watchdog kicks in after script_timeout.
  ctx.timeout_at = get_mono_time() + script_timeout

proc yield_script(self: Worker, unit: Unit) =
  let ctx = unit.script_ctx
  ctx.callback = ctx.saved_callback
  ctx.saved_callback = nil
  self.pause_script()

proc exit(self: Worker, ctx: ScriptCtx, exit_code: int) =
  ctx.exit_code = some(exit_code)
  self.pause_script()
  ctx.running = false

proc load_level(self: Worker, level: string, world: string) =
  var world = world
  if not ?world:
    world = state.config.world
  self.exit(self.active_unit.script_ctx, 0)
  after_boop:
    change_loaded_level(level, world)

proc reset_level(self: Worker) =
  self.exit(self.active_unit.script_ctx, 0)
  after_boop:
    let current_level = state.config.level_dir
    state.config_value.value:
      level_dir = ""
    remove_dir current_level
    state.config_value.value:
      level_dir = current_level

proc ensure_unit_impl[T: Unit](self: Worker, unit: T) {.gcsafe.} =
  if unit notin self.node_map:
    var node = self.template_node_map[$T].copy_tree
    self.map_unit(unit, node)

method ensure_exists(self: Unit, worker: Worker) {.base, gcsafe.} =
  raise_assert "ensure_unit not implemented for " & $self.type

method ensure_exists(self: Player, worker: Worker) =
  worker.ensure_unit_impl(self)

method ensure_exists(self: Bot, worker: Worker) =
  worker.ensure_unit_impl(self)

method ensure_exists(self: Build, worker: Worker) =
  worker.ensure_unit_impl(self)

method ensure_exists(self: Sign, worker: Worker) =
  worker.ensure_unit_impl(self)

proc current_colliders*(self: Worker, unit: Unit, kind: string): seq[Unit] =
  var colliders: seq[Unit]
  state.units.value.walk_tree proc(other: Unit) =
    if unit.collisions.value.any_it(it.id == other.id):
      if kind == "Unit" or kind == "Player" and other of Player or
          kind == "Bot" and other of Bot or kind == "Build" and other of Build or
          kind == "Sign" and other of Sign:
        colliders.add(other)
        other.ensure_exists(self)
  colliders

proc world_name(): string =
  state.config.world

proc level_name(): string =
  state.config.level

proc begin_turn(
    self: Worker,
    unit: Unit,
    direction: Vector3,
    degrees: float,
    lean: bool,
    move_mode: int,
): string =
  assert not degrees.is_nan
  var degrees = floor_mod(degrees, 360)
  let ctx = self.active_unit.script_ctx
  ctx.callback = unit.on_begin_turn(direction, degrees, lean, move_mode)
  ctx.last_ran = MonoTime.default
  if not ctx.callback.is_nil:
    self.pause_script()

proc begin_move(
    self: Worker, unit: Unit, direction: Vector3, steps: float, move_mode: int
) =
  var steps = steps
  var direction = direction
  let ctx = self.active_unit.script_ctx
  if steps < 0:
    steps = steps * -1
    direction = direction * -1
  ctx.callback = unit.on_begin_move(direction, steps, move_mode)
  ctx.last_ran = MonoTime.default
  if not ctx.callback.is_nil:
    self.pause_script()

proc sleep_impl(self: Worker, ctx: ScriptCtx, seconds: float) =
  var duration = 0.0
  ctx.callback = proc(delta: float, _: MonoTime): TaskStates =
    duration += delta
    if seconds > 0 and duration < seconds:
      RUNNING
    elif seconds <= 0 and duration <= 0.5 and ctx.timer > get_mono_time():
      RUNNING
    else:
      DONE
  ctx.last_ran = MonoTime.default
  self.pause_script()

proc hit(self: Unit, unit_b: Unit): bool =
  if not ?unit_b:
    return

  for collision in self.collisions:
    if collision.id == unit_b.id:
      return true

proc find_all[T: Unit](worker: Worker, _: type T): seq[T] =
  var units: seq[T]
  state.units.value.walk_tree proc(unit: Unit) =
    if unit of T:
      unit.ensure_exists(worker)
      units.add T(unit)
  units

proc all_players(worker: Worker): seq[Player] =
  worker.find_all(Player)

proc all_bots(worker: Worker): seq[Bot] =
  worker.find_all(Bot)

proc all_builds(worker: Worker): seq[Build] =
  worker.find_all(Build)

proc all_signs(worker: Worker): seq[Sign] =
  worker.find_all(Sign)

proc all_units(worker: Worker): seq[Unit] =
  worker.find_all(Unit)

proc added_units(worker: Worker): seq[Unit] =
  for unit in worker.find_all(Unit):
    if unit.frame_created == state.frame_count:
      result.add unit

proc echo_console(msg: string) =
  echo(msg)
  logger("info", msg & "\n")
  state.push_flag CONSOLE_VISIBLE

proc dump_stats(label: string) =
  when defined(metrics):
    var stats: string
    {.cast(gcsafe).}:
      stats = $default_registry
    info "dump_stats", label, stats
  else:
    info "dump_stats: build with -d:metrics to enable stats"

proc action_running(self: Unit): bool =
  self.script_ctx.action_running

proc `action_running=`(self: Unit, value: bool) =
  if value:
    self.script_ctx.timer = get_mono_time() + advance_step
  else:
    self.script_ctx.timer = MonoTime.high
  self.script_ctx.action_running = value

proc id(self: Unit): string =
  self.id

proc global(self: Unit): bool =
  GLOBAL in self.global_flags

proc `global=`(self: Unit, global: bool) =
  if global:
    self.global_flags += GLOBAL
  else:
    self.global_flags -= GLOBAL

proc lock(self: Unit): bool =
  LOCK in self.global_flags

proc `lock=`(self: Unit, value: bool) =
  if value:
    self.global_flags += LOCK
  else:
    self.global_flags -= LOCK

proc position(self: Unit): Vector3 =
  units.position(self)

proc local_position(self: Unit): Vector3 =
  self.transform.origin

proc start_position(self: Unit): Vector3 =
  if GLOBAL in self.global_flags:
    self.start_transform.origin
  else:
    self.start_transform.origin.global_from(self.parent)

proc position_set(self: Unit, position: Vector3) =
  var position = position
  if self of Player and position.y <= 0:
    position.y = 0.1

  if GLOBAL in self.global_flags:
    self.transform_value.origin = position
  else:
    self.transform_value.origin = position.local_to(self.parent)

proc start_position_set(self: Unit, position: Vector3) =
  if GLOBAL in self.global_flags:
    self.start_transform.origin = position
  else:
    self.start_transform.origin = position.local_to(self.parent)
  self.global_flags += DIRTY

proc delete(self: Unit) =
  ## Remove the unit from the level and delete its on-disk script + data.
  ## Distinct from the `destroy` method, which only tears down the in-memory
  ## instance.
  if ?self.script_ctx and self.script_ctx.script != "" and
      file_exists(self.script_ctx.script):
    try:
      remove_file(self.script_ctx.script)
    except OSError:
      discard
  let dir = self.data_dir
  if dir != "" and dir_exists(dir):
    try:
      remove_dir(dir)
    except OSError:
      discard
  if self.parent.is_nil:
    state.units -= self
  else:
    self.parent.units -= self

proc speed(self: Unit): float =
  self.speed

const ASAP_VALUE = 0

proc `speed=`(self: Unit, speed: float) =
  if self of Build and speed == ASAP_VALUE:
    Build(self).begin_asap()
    self.speed = 0
  else:
    if self of Build:
      Build(self).end_asap()
    self.speed = speed

proc scale(self: Unit): float =
  types.scale(self)

proc `scale=`(self: Unit, scale: float) =
  types.`scale=`(self, scale)

proc color(self: Unit): Colors =
  action_index self.color_value.value

proc `color=`(self: Unit, color: Colors) =
  types.`color=`(self, ACTION_COLORS[color])

proc show(self: Unit): bool =
  VISIBLE in self.global_flags

proc `show=`(self: Unit, value: bool) =
  if value:
    self.global_flags += VISIBLE
  else:
    self.global_flags -= VISIBLE

proc rotation(self: Unit): float =
  if self of Player:
    result = Player(self).rotation
  else:
    let e = self.transform.basis.orthonormalized.get_euler
    # Y-axis rotation (yaw) in radians, convert to degrees
    # Normalize to -180..180 range
    var degrees = rad_to_deg(e.y)
    while degrees > 180.0:
      degrees -= 360.0
    while degrees < -180.0:
      degrees += 360.0
    result = degrees

proc `rotation=`(self: Unit, degrees: float) =
  var t = Transform.init
  if self of Player:
    Player(self).rotation_value.touch degrees
    t.origin = self.transform.origin
  else:
    t = Transform.init
    var s = self.scale
    t = t.rotated(UP, deg_to_rad(degrees)).scaled(vec3(s, s, s))
    t.origin = self.transform.origin
  self.transform = t

proc sees(
    worker: Worker, self: Unit, target: Unit, distance: float
): Future[bool] =
  result = Future.init(bool, "sees")

  if target == state.player and FLYING in state.local_flags:
    result.complete(false)
    return

  if ?target and (self of Build or self of Bot):
    self.sight_query = SightQuery(target: target, distance: distance)
  else:
    result.complete(false)
    return

  let future = result
  self.script_ctx.callback = proc(delta: float, timeout: MonoTime): TaskStates =
    let query = self.sight_query
    if ?query.answer:
      future.complete(query.answer.get)
      result = DONE
    else:
      result = RUNNING

  self.script_ctx.last_ran = MonoTime.default
  worker.pause_script()

proc frame_count(): int =
  state.frame_count

proc frame_created(unit: Unit): int =
  unit.frame_created

proc drop_transform(unit: Unit): Transform =
  if unit of Bot:
    result = Transform.init
  elif unit of Build:
    result = Build(unit).draw_transform
    result.origin = result.origin.snapped(vec3(1, 1, 1))
    result = result.translated(FORWARD * 0.51)
    result.origin = result.origin - (FORWARD + LEFT + DOWN) * 0.5
  else:
    raise ObjectConversionDefect.init("Unknown unit type")

proc reset(self: Unit, clear: bool) =
  if clear:
    if self of Build:
      Build(self).reset()
    elif self of Bot:
      Bot(self).reset()
  else:
    if self of Build:
      Build(self).reset_state()
    elif self of Bot:
      Bot(self).reset_state()

# Bot bindings

proc play(self: Bot, animation_name: string) =
  self.animation = animation_name

# Build bindings

proc drawing(self: Build): bool =
  self.drawing

proc `drawing=`(self: Build, drawing: bool) =
  self.drawing = drawing

proc initial_position(self: Build): Vector3 =
  self.initial_position

proc draw_position(self: Build): Vector3 =
  self.position + self.draw_transform.origin

proc draw_position_set(self: Build, position: Vector3) =
  if GLOBAL in self.global_flags:
    self.draw_transform_value.origin = position - self.position
  else:
    self.draw_transform_value.origin =
      (position - self.position).local_to(self.parent)

proc save(self: Build, name: string) =
  self.save_points[name] =
    (self.draw_transform, self.color_value.value, self.drawing)

proc restore(self: Build, name: string) =
  (self.draw_transform, self.color_value.value, self.drawing) =
    self.save_points[name]

# Player binding

proc playing(self: Unit): bool =
  PLAYING in state.local_flags

proc `playing=`*(self: Unit, value: bool) =
  state.set_flag PLAYING, value

proc god(self: Unit): bool =
  GOD in state.local_flags

proc `god=`*(self: Unit, value: bool) =
  state.set_flag GOD, value

proc flying(self: Unit): bool =
  FLYING in state.local_flags

proc `flying=`*(self: Unit, value: bool) =
  state.set_flag FLYING, value

proc running(self: Unit): bool =
  ALT_WALK_SPEED in state.local_flags

proc `running=`*(self: Unit, value: bool) =
  state.set_flag ALT_WALK_SPEED, value

proc tool(self: Unit): int =
  int(state.tool)

proc `tool=`(self: Unit, value: int) =
  state.tool = Tools(value)

proc open_sign(self: Unit): Sign =
  state.open_sign

proc `open_sign=`(self: Unit, value: Sign) =
  state.open_sign = value

proc executing_player(worker: Worker): Player =
  let active = worker.active_unit
  if active of Player:
    return Player(active)

  let owner_id = \"player-{active.code.owner}"
  for unit in state.units.value:
    if unit of Player:
      let player = Player(unit)
      if player.id == owner_id:
        player.ensure_exists(worker)
        return player

  return nil

# World bindings

proc environment(_: PNode): string =
  if ?state.config.environment_override:
    state.config.environment_override
  else:
    state.config.environment

proc `environment=`(_: PNode, mode: string) =
  state.config_value.value:
    environment_override = mode

proc megapixels(_: PNode): float =
  state.config.megapixels

proc `megapixels=`(_: PNode, pixels: float) =
  state.config_value.value:
    megapixels = pixels

# Sign bindings

proc new_markdown_sign(
    self: Worker,
    unit: Unit,
    pnode: PNode,
    message: string,
    more: string,
    width: float,
    height: float,
    size: int,
    billboard: bool,
): Unit =
  result = Sign.init(
    message,
    more = more,
    owner = self.active_unit,
    transform = drop_transform(unit),
    width = width,
    height = height,
    size = size,
    billboard = billboard,
  )

  info "creating sign", id = result.id
  self.map_unit(result, pnode)
  unit.units.add(result)

proc update_markdown_sign(
    self: Worker,
    unit: Sign,
    message: string,
    more: string,
    width: float,
    height: float,
    size: int,
    billboard: bool,
) =
  unit.width = width
  unit.height = height
  unit.size = size
  unit.billboard = billboard
  unit.more = more
  unit.message = message

proc `width=`(self: Sign, value: float) =
  types.`width=`(self, value)
  self.message_value.touch self.message

proc `height=`(self: Sign, value: float) =
  types.`height=`(self, value)
  self.message_value.touch self.message

proc `size=`(self: Sign, value: int) =
  types.`size=`(self, value)
  self.message_value.touch self.message

proc message(self: Sign): string =
  self.message_value.value

proc open(self: Sign): bool =
  state.open_sign == self

proc `open=`(self: Sign, value: bool) =
  if value:
    state.open_sign = self
  elif not value and self.open:
    state.open_sign = nil

proc coding(self: Worker, unit: Unit): Unit =
  if unit == state.player:
    if ?state.open_unit:
      state.open_unit.ensure_exists(self)
      result = state.open_unit

proc `coding=`(self: Unit, value: Unit) =
  state.open_unit = value

proc signal_test_complete(self: Worker, exit_code: int) =
  state.test_exit_code = exit_code

proc find_block_at(position: Vector3): Option[VoxelInfo] =
  for unit in state.units.value:
    if unit of Build:
      let build = Build(unit)
      let local_pos = position.local_to(build)
      if local_pos in build:
        let info = build.voxel_info(local_pos)
        if info.kind != HOLE and info.color != ACTION_COLORS[ERASER]:
          return some(info)
    for child in unit.units.value:
      if child of Build:
        let build = Build(child)
        let local_pos = position.local_to(build)
        if local_pos in build:
          let info = build.voxel_info(local_pos)
          if info.kind != HOLE and info.color != ACTION_COLORS[ERASER]:
            return some(info)
  none(VoxelInfo)

proc has_block_at(position: Vector3): bool =
  find_block_at(position).is_some

proc block_color_at(position: Vector3): Colors =
  let block_info = find_block_at(position)
  if block_info.is_some:
    action_index(block_info.get.color)
  else:
    ERASER

proc draw_voxel(self: Build, position: Vector3, color: Colors) =
  ## Paint a COMPUTED voxel. Goes through Build.draw, which only writes to
  ## local_voxels (not local_edits), so the block is regenerated when the
  ## script reloads and isn't bloating the save file. Backs fill_box,
  ## fill_sphere, fill_cylinder, and place.
  let info: VoxelInfo = (COMPUTED, ACTION_COLORS[color])
  self.draw(position, info)

proc place_block(self: Build, position: Vector3, color: Colors) =
  ## Place a persistent MANUAL voxel. The block is saved to local_edits and
  ## survives reload. For programmatic block-placement use draw_voxel.
  let info: VoxelInfo = (MANUAL, ACTION_COLORS[color])
  self.add_voxel(position, info)
  self.voxels.set_edit(position, info)

proc save_level_now() =
  serializers.save_level(state.config.level_dir, force = true)

proc reload_unit(self: Build) =
  self.voxels.clear()
  self.voxels.rebuild_local_edits()
  self.restore_edits()
  self.reset_bounds()

# End of bindings

proc bridge_to_vm*(worker: Worker) =
  # host_bridge_utils.nim is expecting a var called `result`. Fix this.
  var result = worker

  worker.interpreter.implement_routine "enu",
    "base_bridge_private",
    "read_enu_script",
    proc(a: VmArgs) {.gcsafe.} =
      let filename = get_string(a, 0)
      let full_path =
        if filename.is_absolute:
          filename
        else:
          state.config_value.value.level_dir / "generated" / filename

      let normalized_path = full_path.replace("\\", "/").normalized_path()
      debug "reading script source", path = normalized_path
      if "/scripts/" notin normalized_path:
        raise ValueError.init(
          "Direct file access blocked for security. Scripts can only be read from within the scripts directory. Attempted: " &
            normalized_path
        )
      set_result(a, to_result(read_file(full_path)))

  result.bridged_from_vm "vm_bridge_utils", get_last_error

  result.bridged_from_vm "base_bridge",
    register_active, register_template_node, echo_console, new_instance,
    exec_instance, hit, exit, global, `global=`, position, local_position,
    rotation, `rotation=`, id, glow, `glow=`, speed, `speed=`, scale, `scale=`,
    velocity, `velocity=`, active_unit, color, `color=`, sees, start_position,
    wake, frame_count, write_stack_trace, show, `show=`, frame_created, lock,
    `lock=`, reset, press_action, load_level, level_name, world_name,
    reset_level, current_colliders, added_units, all_players, all_builds,
    all_bots, all_signs, all_units, signal_test_complete, now_seconds,
    dump_stats

  result.bridged_from_vm "base_bridge_private",
    action_running, `action_running=`, yield_script, begin_turn, begin_move,
    sleep_impl, position_set, start_position_set, delete, keep_alive,
    new_markdown_sign, update_markdown_sign

  result.bridged_from_vm "bots", play

  result.bridged_from_vm "builds",
    drawing, `drawing=`, initial_position, save, restore, draw_position,
    draw_position_set, has_block_at, block_color_at, begin_asap, end_asap,
    draw_voxel, save_level_now, reload_unit

  result.bridged_from_vm "builds_private", place_block

  result.bridged_from_vm "signs",
    message, `message=`, more, `more=`, height, `height=`, width, `width=`,
    size, `size=`, open, `open=`, billboard, `billboard=`

  result.bridged_from_vm "players",
    playing, `playing=`, god, `god=`, flying, `flying=`, tool, `tool=`, coding,
    `coding=`, running, `running=`, open_sign, `open_sign=`, executing_player

  result.bridged_from_vm "worlds",
    environment, `environment=`, megapixels, `megapixels=`
