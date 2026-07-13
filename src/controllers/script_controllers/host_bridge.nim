import std/[os, macros, math, asyncfutures, hashes, times]
import locks except Lock
import pkg/godot except print, Color
import pkg/chroma
import pkg/compiler/vm except get_int
from pkg/compiler/vm {.all.} import stack_trace_aux
import pkg/compiler/ast except new_node
import pkg/compiler/[vmdef, renderer, msgs]
import pkg/metrics

import godotapi/[spatial, ray_cast]
import
  core, models/[states, bots, builds, things, colors, signs, serializers, voxels]
import libs/[interpreters, eval]
import enu/shared/errors

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

proc map_thing(self: Worker, thing: Thing, pnode: PNode) =
  debug "mapping pnode ", hash = pnode.hash, thing = thing.id
  self.thing_map[pnode] = thing
  self.node_map[thing] = pnode

proc unmap_thing*(self: Worker, thing: Thing) =
  if thing in self.node_map:
    debug "unmapping node ", hash = self.node_map[thing].hash, thing = thing.id
    self.thing_map.del self.node_map[thing]
    self.node_map.del thing

proc write_stack_trace(self: Worker) =
  private_access ScriptCtx

  let ctx = self.active_thing.script_ctx
  {.gcsafe.}:
    msg_writeln(
      ctx.ctx.config, "stack trace: (most recent call last)", {msg_no_unit_sep}
    )

    stack_trace_aux(ctx.ctx, ctx.tos, ctx.pc)

proc get_thing(self: Worker, a: VmArgs, pos: int): Thing {.gcsafe.} =
  let pnode = a.get_node(pos)
  if pnode.kind != nkNilLit:
    {.gcsafe.}:
      result = self.thing_map[pnode]

proc get_bot(self: Worker, a: VmArgs, pos: int): Bot =
  let thing = self.get_thing(a, pos)
  assert not thing.is_nil and thing of Bot
  Bot(thing)

proc get_build(self: Worker, a: VmArgs, pos: int): Build =
  let thing = self.get_thing(a, pos)
  assert not thing.is_nil and thing of Build
  Build(thing)

proc get_sign(self: Worker, a: VmArgs, pos: int): Sign =
  let pnode = a.get_node(pos)
  if pnode.kind != nkNilLit:
    let thing = self.get_thing(a, pos)
    assert not thing.is_nil and thing of Sign
    result = Sign(thing)

proc to_node(self: Worker, thing: Thing): PNode =
  if ?thing:
    if thing notin self.node_map:
      fail \"thing `{thing.id}` not in node_map"
    self.node_map[thing]
  else:
    ast.new_node(nkNilLit)

proc to_node[T: Thing](self: Worker, things: seq[T]): PNode =
  var node = ast.new_node(nkBracketExpr)
  for thing in things:
    if ?thing:
      node.add self.to_node(thing)
    else:
      node.add ast.new_node(nk_nil_lit)
  result = node

# Common bindings

# The queued action carries its edge in the first byte ('+' press,
# '-' release); game.nim's watcher decodes it. press_action leaves the
# action held — godot never auto-releases a synthetic action, so pair it
# with release_action (a held action pins get_action_strength at 1.0,
# and a repeated press reads as a double-tap).
proc press_action(self: Worker, name: string) =
  state.queued_action = "+" & name

proc release_action(self: Worker, name: string) =
  state.queued_action = "-" & name

proc register_template_node(self: Worker, pnode: PNode, name: string) =
  self.template_node_map[name] = pnode

proc register_active(self: Worker, pnode: PNode) =
  assert not self.active_thing.is_nil
  self.map_thing(self.active_thing, pnode)

proc new_instance(self: Worker, src: Thing, dest: PNode) =
  let id =
    src.id & "_" & self.active_thing.id & "_instance_" &
    $(self.active_thing.things.len + 1)

  var clone = src.clone(self.active_thing, id)
  assert not clone.is_nil
  clone.spawned_by = self.active_thing.id
  clone.script_ctx = ScriptCtx.init(
    owner = clone, clone_of = src, interpreter = self.interpreter
  )

  self.map_thing(clone, dest)

  debug "adding to active thing",
    thing = clone.id, active_thing = self.active_thing.id

  self.active_thing.things.add(clone)

proc exec_instance(self: Worker, thing: Thing) =
  let active = self.active_thing
  let ctx = thing.script_ctx
  self.active_thing = thing
  defer:
    self.active_thing = active
  ctx.fuel = script_fuel
  ctx.running = ctx.call_proc("run_script", self.node_map[thing], true).paused

proc active_thing(self: Worker): Thing =
  self.active_thing

proc wake(self: Thing) =
  self.script_ctx.timer = get_mono_time()

proc pause_script(self: Worker) =
  self.active_thing.global_flags -= SCRIPT_INITIALIZING
  self.active_thing.script_ctx.pause()

proc keep_alive(ctx: ScriptCtx) =
  ## Refill the script's instruction budget. For long non-yielding loops
  ## (eg. spatial queries from eval) that have legitimate work to do but no
  ## reason to yield. Call periodically — the watchdog kicks in when the
  ## budget runs out.
  ctx.fuel = script_fuel

proc yield_script(self: Worker, thing: Thing) =
  let ctx = thing.script_ctx
  ctx.callback = ctx.saved_callback
  ctx.saved_callback = nil
  self.pause_script()

proc exit(self: Worker, ctx: ScriptCtx, exit_code: int) =
  ctx.exit_code = some(exit_code)
  self.pause_script()
  ctx.running = false

proc to_thing_id*(requested_name: string): string =
  ## Convert a user-facing prototype name (CamelCase or any-case) into
  ## the on-disk thing id `build_<snake_case>`. `Tree` -> `build_tree`,
  ## `DiningChair` -> `build_dining_chair`, `bed_queen` ->
  ## `build_bed_queen`. Already-prefixed names are kept as-is.
  if requested_name == "":
    return ""
  var snake = ""
  for i, c in requested_name:
    if c in {'A' .. 'Z'}:
      if i > 0 and requested_name[i - 1] notin {'_', 'A' .. 'Z'}:
        snake.add '_'
      snake.add char(ord(c) - ord('A') + ord('a'))
    else:
      snake.add c
  if snake.starts_with("build_") or snake.starts_with("bot_"):
    snake
  else:
    "build_" & snake

proc claim_name(self: Worker, requested: string) =
  ## Called from the `name` macro at the top of a prototype script.
  ## If the thing's on-disk id already matches `requested`, no-ops.
  ## If a conflicting thing already exists in the level, raises a
  ## script error. Otherwise, schedules a rename of the script + data
  ## files and exits the current script — the file watcher then
  ## reloads the thing under the new id.
  let thing = self.active_thing
  if thing.is_nil or not ?thing.script_ctx:
    return
  # Every named thing is a prototype. Apply the level's prototype-visibility
  # default before any user `show = ...` in the script body runs. If the
  # script sets `show` explicitly later it wins (assignments run after
  # claim_name in the macro-generated code).
  if not state.show_prototypes:
    thing.global_flags -= VISIBLE
  let target_id = to_thing_id(requested)
  if target_id == "" or thing.id == target_id:
    return

  let
    new_script = state.config.script_dir / (target_id & ".nim")
    new_data_dir = state.config.data_dir / target_id
  if file_exists(new_script) or dir_exists(new_data_dir):
    raise ValueError.init(
      "The name '" & requested & "' conflicts with the existing thing '" &
        target_id & "'. Choose a different name."
    )

  let
    old_id = thing.id
    old_script = thing.script_ctx.script
    old_data_dir = state.config.data_dir / old_id
    old_data_file = old_data_dir / (old_id & ".json")
    new_data_file = new_data_dir / (target_id & ".json")

  self.exit(thing.script_ctx, 0)
  after_boop:
    # Capture the file content with id rewrites before any moves.
    var data_content = ""
    if file_exists(old_data_file):
      data_content =
        read_file(old_data_file).replace(
          "\"" & old_id & "\"", "\"" & target_id & "\""
        )

    if dir_exists(old_data_dir):
      move_dir(old_data_dir, new_data_dir)
      let inner_old = new_data_dir / (old_id & ".json")
      if file_exists(inner_old):
        move_file(inner_old, new_data_file)
      if data_content != "" and file_exists(new_data_file):
        write_file(new_data_file, data_content)

    if file_exists(old_script):
      move_file(old_script, new_script)

    # Drop the in-memory thing; the file watcher picks up the new
    # `data/<target_id>/<target_id>.json` on its next pass.
    if thing.parent.is_nil:
      state.things -= thing
    else:
      thing.parent.things -= thing
    save_level(state.config.level_dir)

proc load_level(self: Worker, level: string, world: string) =
  var world = world
  if not ?world:
    world = state.config.world
  self.exit(self.active_thing.script_ctx, 0)
  after_boop:
    change_loaded_level(level, world)

proc reset_level(self: Worker) =
  self.exit(self.active_thing.script_ctx, 0)
  after_boop:
    let current_level = state.config.level_dir
    state.config_value.value:
      level_dir = ""
    remove_dir current_level
    state.config_value.value:
      level_dir = current_level

proc ensure_thing_impl[T: Thing](self: Worker, thing: T) {.gcsafe.} =
  if thing notin self.node_map:
    var node = self.template_node_map[$T].copy_tree
    self.map_thing(thing, node)

method ensure_exists(self: Thing, worker: Worker) {.base, gcsafe.} =
  raise_assert "ensure_thing not implemented for " & $self.type

method ensure_exists(self: Player, worker: Worker) =
  worker.ensure_thing_impl(self)

method ensure_exists(self: Bot, worker: Worker) =
  worker.ensure_thing_impl(self)

method ensure_exists(self: Build, worker: Worker) =
  worker.ensure_thing_impl(self)

method ensure_exists(self: Sign, worker: Worker) =
  worker.ensure_thing_impl(self)

proc current_colliders*(self: Worker, thing: Thing, kind: string): seq[Thing] =
  var colliders: seq[Thing]
  state.things.value.walk_tree proc(other: Thing) =
    if thing.collisions.value.any_it(it.id == other.id):
      if kind == "Thing" or kind == "Player" and other of Player or
          kind == "Bot" and other of Bot or kind == "Build" and other of Build or
          kind == "Sign" and other of Sign:
        colliders.add(other)
        other.ensure_exists(self)
  colliders

proc world_name(): string =
  state.config.world

proc level_name(): string =
  state.config.level

proc color_to_lower(c: Color): string =
  ## Block-log label: the name for named colors, hex for static ones.
  let named = c.action_index
  if named != ERASER or c == ACTION_COLORS[ERASER]:
    to_lower_ascii($named)
  else:
    "#" & to_lower_ascii(c.to_html_hex)

proc block_log(self: Thing): string =
  ## Recent blocks the player has placed (or erased) via the in-game block
  ## tools, oldest first. Each line: "ago=<sec>s color=<c> thing=<id>
  ## local=(x,y,z) global=(x,y,z)". Cap is BLOCK_LOG_CAP from builds.nim.
  if not (self of Player):
    return ""
  let now = get_mono_time()
  for entry in Player(self).block_log_entries.value:
    let ago = (now - entry.timestamp).in_milliseconds.float / 1000.0
    result &=
      "ago=" & $ago & "s color=" & color_to_lower(entry.color) & " thing=" &
      entry.thing_id & " local=(" & $entry.local_position.x & "," &
      $entry.local_position.y & "," & $entry.local_position.z & ") global=(" &
      $entry.global_position.x & "," & $entry.global_position.y & "," &
      $entry.global_position.z & ")\n"

proc clear_block_log(self: Thing) =
  if self of Player:
    Player(self).block_log_entries.clear

proc begin_turn(
    self: Worker,
    thing: Thing,
    direction: Vector3,
    degrees: float,
    lean: bool,
    move_mode: int,
): string =
  assert not degrees.is_nan
  var degrees = floor_mod(degrees, 360)
  let ctx = self.active_thing.script_ctx
  ctx.callback = thing.on_begin_turn(direction, degrees, lean, move_mode)
  ctx.last_ran = MonoTime.default
  if not ctx.callback.is_nil:
    self.pause_script()

proc begin_move(
    self: Worker, thing: Thing, direction: Vector3, steps: float, move_mode: int
) =
  var steps = steps
  var direction = direction
  let ctx = self.active_thing.script_ctx
  if steps < 0:
    steps = steps * -1
    direction = direction * -1
  ctx.callback = thing.on_begin_move(direction, steps, move_mode)
  ctx.last_ran = MonoTime.default
  if not ctx.callback.is_nil:
    self.pause_script()

proc sleep_impl(self: Worker, ctx: ScriptCtx, seconds: float) =
  # seconds  > 0 : park for that long.
  #          < 0 : no-arg nap — up to half a second, waking early if the
  #                thing is bumped (ctx.timer is pulled near by a collision).
  #         == 0 : yield exactly one tick. Used at the end of every script
  #                (a bare `sleep 0` before the wrapper returns) so control
  #                returns to the engine once before the VM tears the module
  #                down; the script then completes on the next tick and
  #                end_asap publishes its drawing — no 0.5s settle delay.
  var duration = 0.0
  ctx.callback = proc(delta: float, _: MonoTime): TaskStates =
    duration += delta
    if seconds > 0 and duration < seconds:
      RUNNING
    elif seconds < 0 and duration <= 0.5 and ctx.timer > get_mono_time():
      RUNNING
    else:
      DONE
  ctx.last_ran = MonoTime.default
  self.pause_script()

proc hit(self: Thing, thing_b: Thing): bool =
  if not ?thing_b:
    return

  for collision in self.collisions:
    if collision.id == thing_b.id:
      return true

proc find_all[T: Thing](worker: Worker, _: type T): seq[T] =
  var things: seq[T]
  state.things.value.walk_tree proc(thing: Thing) =
    if thing of T:
      thing.ensure_exists(worker)
      things.add T(thing)
  things

proc all_players(worker: Worker): seq[Player] =
  worker.find_all(Player)

proc all_bots(worker: Worker): seq[Bot] =
  worker.find_all(Bot)

proc all_builds(worker: Worker): seq[Build] =
  worker.find_all(Build)

proc all_signs(worker: Worker): seq[Sign] =
  worker.find_all(Sign)

proc all_things(worker: Worker): seq[Thing] =
  worker.find_all(Thing)

proc added_things(worker: Worker): seq[Thing] =
  for thing in worker.find_all(Thing):
    if thing.frame_created == state.frame_count:
      result.add thing

proc echo_console(msg: string) =
  echo(msg)
  logger("info", msg & "\n")
  if state.config.auto_show_console:
    state.push_flag CONSOLE_VISIBLE

proc dump_stats(label: string) =
  when defined(metrics):
    var stats: string
    {.cast(gcsafe).}:
      stats = $default_registry
    info "dump_stats", label, stats
  else:
    info "dump_stats: build with -d:metrics to enable stats"

proc action_running(self: Thing): bool =
  self.script_ctx.action_running

proc `action_running=`(self: Thing, value: bool) =
  if value:
    self.script_ctx.timer = get_mono_time() + advance_step
  else:
    self.script_ctx.timer = MonoTime.high
  self.script_ctx.action_running = value

proc id(self: Thing): string =
  self.id

proc global(self: Thing): bool =
  GLOBAL in self.global_flags

proc `global=`(self: Thing, global: bool) =
  if global:
    self.global_flags += GLOBAL
  else:
    self.global_flags -= GLOBAL

proc lock(self: Thing): bool =
  LOCK in self.global_flags

proc `lock=`(self: Thing, value: bool) =
  if value:
    self.global_flags += LOCK
  else:
    self.global_flags -= LOCK

proc position(self: Thing): Vector3 =
  things.position(self)

proc local_position(self: Thing): Vector3 =
  self.transform.origin

proc start_position(self: Thing): Vector3 =
  if GLOBAL in self.global_flags:
    self.start_transform.origin
  else:
    self.start_transform.origin.global_from(self.parent)

proc position_set(self: Thing, position: Vector3) =
  var position = position
  if self of Player and position.y <= 0:
    position.y = 0.1

  if GLOBAL in self.global_flags:
    self.set_pivot_local(position)
  else:
    self.set_pivot_local(position.local_to(self.parent))

proc start_position_set(self: Thing, position: Vector3) =
  if GLOBAL in self.global_flags:
    self.start_transform.origin = position
  else:
    self.start_transform.origin = position.local_to(self.parent)
  self.global_flags += DIRTY

proc reset_anchor(self: Thing) =
  ## Reset the thing's anchor to identity. Used at the start of an
  ## `anchor:` block so the body's turtle commands accumulate from a
  ## clean pivot.
  self.anchor = Transform.init

proc capture_start_transform(self: Thing) =
  ## Stamp the thing's current pose as its spawn pose. Called at the end of
  ## `.new()` so a clone's `start_position` (and reset target) is the point
  ## it was spawned at, not the spawner's transform it was seeded with.
  self.start_transform = self.transform

proc delete(self: Thing) =
  ## Remove the thing from the level and delete its on-disk script + data.
  ## Distinct from the `destroy` method, which only tears down the in-memory
  ## instance.

  # Evacuate descendants we don't own so they outlive us: real things, the
  # player, and instances spawned elsewhere (e.g. one adopted onto us to ride).
  # Our own instances (`spawned_by == self.id`) stay and are torn down in the
  # cascade when we're removed below — but the cascade is recursive, so a
  # foreign thing adopted onto one of our instances must be evacuated too: we
  # recurse through our own instances and evacuate the top-most foreign thing of
  # each branch (its own subtree rides along with it). Collected first
  # (reparenting mutates the tree), and done here, before removal, so it isn't
  # re-entrant with the destroy cascade (which mutating ed mid-teardown would
  # be).
  var foreign: seq[Thing]
  proc collect(children: seq[Thing]) =
    for child in children:
      if child.spawned_by != self.id:
        foreign.add child
      else:
        collect(child.things.value)

  collect(self.things.value)
  for thing in foreign:
    thing.reparent_to_root()

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
    state.things -= self
  else:
    self.parent.things -= self

proc adopt(self: Thing, thing: Thing) =
  ## Make `thing` ride `self` (e.g. a moving platform): move it from its current
  ## things collection into `self.things` and nest its node under `self`'s, so the
  ## engine composes transforms and `thing` follows `self`. Bots don't auto-ride a
  ## moving platform — this is how you make them. Ownership moves with membership
  ## for now (`self` owns `thing` until destructor-driven teardown lands — see
  ## getenu/enu#65). `TRANSFERRING` keeps the remove/add from tearing the thing
  ## down (it's a move, not a delete).
  if thing == self or thing.parent == self:
    return
  # Adopting an ancestor would make parent links circular — every parent walk
  # (local_to, world_from, walk_tree) would then loop forever and hang the
  # worker.
  var ancestor = self.parent
  while ?ancestor:
    if ancestor == thing:
      logger("err", "can't adopt " & thing.id & ": it contains " & self.id)
      return
    ancestor = ancestor.parent
  # Only top-level things can be adopted for now: the node reparents off the
  # GLOBAL flag's removed-edge, and a nested thing has no GLOBAL flag to remove —
  # the model would move but the node would stay under the old parent. `release`
  # first. (Proper chained adoption comes with destructor-driven teardown,
  # getenu/enu#65.)
  if ?thing.parent:
    logger(
      "err",
      "can't adopt " & thing.id & ": it's already on " & thing.parent.id &
        "; release it first",
    )
    return
  thing.global_flags += TRANSFERRING
  self.things.add thing
  state.things -= thing
  thing.parent = self
  thing.global_flags -= GLOBAL
  # World -> parent-local through the platform's full transform chain, so
  # adopting onto an already-rotated platform lands at the right local spot.
  thing.transform_value.origin = thing.transform.origin.local_into(self)
  after_boop:
    thing.global_flags -= TRANSFERRING

proc release(self: Thing) =
  ## Reverse of `adopt`: re-root `self` to the top-level things collection and
  ## restore its world transform, so it stops riding its parent.
  self.reparent_to_root()

proc speed(self: Thing): float =
  types.speed(self)

const ASAP_VALUE = 0

proc `speed=`(self: Thing, speed: float) =
  if self of Build and speed == ASAP_VALUE:
    Build(self).begin_asap()
    types.`speed=`(self, 0.0)
  else:
    if self of Build:
      Build(self).end_asap()
    types.`speed=`(self, speed)

proc scale(self: Thing): float =
  types.scale(self)


proc color(self: Thing): Color =
  self.color_value.value

proc `color=`(self: Thing, color: Color) =
  types.`color=`(self, color)

proc show(self: Thing): bool =
  VISIBLE in self.global_flags

proc `show=`(self: Thing, value: bool) =
  if value:
    self.global_flags += VISIBLE
  else:
    self.global_flags -= VISIBLE

# `rotation` (the anchor-aware yaw getter) lives in models/things — shared
# with external agents that pose things.

proc `rotation=`(self: Thing, degrees: float) =
  if self of Player:
    Player(self).rotation_value.touch degrees
    var t = Transform.init
    t.origin = self.transform.origin
    self.transform = t
  else:
    var s = self.scale
    var pivot_basis = Transform.init.basis
      .rotated(UP, deg_to_rad(degrees))
      .scaled(vec3(s, s, s))
    self.set_pivot_basis(pivot_basis)

proc `scale=`(self: Thing, scale: float) =
  types.`scale=`(self, scale)
  if self of Player:
    return
  # Compose scale into transform.basis synchronously, the same way
  # `rotation=` does — the model is the single source of truth. Godot has
  # no separate scale storage (the node derives its scale from the basis),
  # so previously scale only reached the basis asynchronously, via a
  # node→model writeback in build_node/bot_node that raced with — and
  # clobbered — a concurrent `rotation=`. Doing it here removes the race.
  let degrees = self.rotation
  let pivot_basis = Transform.init.basis
    .rotated(UP, deg_to_rad(degrees))
    .scaled(vec3(scale, scale, scale))
  self.set_pivot_basis(pivot_basis)

proc sees(
    worker: Worker, self: Thing, target: Thing, distance: float
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

proc frame_created(thing: Thing): int =
  thing.frame_created

proc drop_transform(thing: Thing): Transform =
  if thing of Bot:
    result = Transform.init
  elif thing of Build:
    result = Build(thing).draw_transform
    result.origin = result.origin.snapped(vec3(1, 1, 1))
    result = result.translated(FORWARD * 0.51)
    result.origin = result.origin - (FORWARD + LEFT + DOWN) * 0.5
  else:
    raise ObjectConversionDefect.init("Unknown thing type")

proc reset(self: Thing, clear: bool) =
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

proc advance(self: Build, steps: float) =
  ## Translate the turtle's draw_position by `steps` along its current
  ## forward direction. Bypasses begin_move (and the speed/ASAP toggle
  ## that goes with it). Used by `wall` / `floor` so the turtle ends up
  ## at the far end of the shape without paying for the forward
  ## animation or risking the speed-toggle render race.
  let offset = self.draw_transform.basis.xform(FORWARD) * steps
  self.draw_transform_value.origin = self.draw_transform.origin + offset
  self.sync_turtle()

proc draw_position_set(self: Build, position: Vector3) =
  if GLOBAL in self.global_flags:
    self.draw_transform_value.origin = position - self.position
  else:
    self.draw_transform_value.origin =
      (position - self.position).local_to(self.parent)
  self.sync_turtle()

proc pen(self: Build): Pen =
  (self.draw_transform, self.color_value.value, self.drawing)

proc pen_set(self: Build, value: Pen) =
  # Assign each part explicitly: tuple unpacking onto accessor calls
  # compiles but silently writes into the getters' temporaries.
  self.draw_transform = value.position
  self.color_value.value = value.color
  self.drawing = value.drawing

# Player binding

proc playing(self: Thing): bool =
  PLAYING in state.local_flags

proc `playing=`*(self: Thing, value: bool) =
  state.set_flag PLAYING, value

proc god(self: Thing): bool =
  GOD in state.local_flags

proc `god=`*(self: Thing, value: bool) =
  state.set_flag GOD, value

proc flying(self: Thing): bool =
  FLYING in state.local_flags

proc `flying=`*(self: Thing, value: bool) =
  state.set_flag FLYING, value

proc running(self: Thing): bool =
  ALT_WALK_SPEED in state.local_flags

proc `running=`*(self: Thing, value: bool) =
  state.set_flag ALT_WALK_SPEED, value

proc tool(self: Thing): int =
  int(state.tool)

proc `tool=`(self: Thing, value: int) =
  state.tool = Tools(value)

proc tools_has(self: Thing, tool: int): bool =
  Tools(tool) in state.tools

proc tools_incl(self: Thing, tool: int) =
  state.tools += Tools(tool)

proc tools_excl(self: Thing, tool: int) =
  state.tools -= Tools(tool)

proc tools_clear(self: Thing) =
  state.tools.clear()

proc open_sign(self: Thing): Sign =
  state.open_sign

proc `open_sign=`(self: Thing, value: Sign) =
  state.open_sign = value

proc executing_player(worker: Worker): Player =
  let active = worker.active_thing
  if active of Player:
    return Player(active)

  let owner_id = \"player-{active.code.owner}"
  for thing in state.things.value:
    if thing of Player:
      let player = Player(thing)
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
    thing: Thing,
    pnode: PNode,
    message: string,
    more: string,
    width: float,
    height: float,
    size: int,
    billboard: bool,
): Thing =
  result = Sign.init(
    message,
    more = more,
    owner = self.active_thing,
    transform = drop_transform(thing),
    width = width,
    height = height,
    size = size,
    billboard = billboard,
  )

  info "creating sign", id = result.id
  self.map_thing(result, pnode)
  thing.things.add(result)

proc update_markdown_sign(
    self: Worker,
    thing: Sign,
    message: string,
    more: string,
    width: float,
    height: float,
    size: int,
    billboard: bool,
) =
  thing.width = width
  thing.height = height
  thing.size = size
  thing.billboard = billboard
  thing.more = more
  thing.message = message

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

proc coding(self: Worker, thing: Thing): Thing =
  if thing == state.player:
    if ?state.open_thing:
      state.open_thing.ensure_exists(self)
      result = state.open_thing

proc `coding=`(self: Thing, value: Thing) =
  state.open_thing = value

proc signal_test_complete(self: Worker, exit_code: int) =
  state.test_exit_code = exit_code

proc find_block_at(position: Vector3): Option[VoxelInfo] =
  # local_into is the FULL inverse transform (scale + rotation), unlike
  # local_to which only subtracts origins — so a query against a scaled or
  # rotated build lands on the right local voxel instead of a world-space
  # coordinate the build never stored there.
  for thing in state.things.value:
    if thing of Build:
      let build = Build(thing)
      let local_pos = position.local_into(build)
      if local_pos in build:
        let info = build.voxel_info(local_pos)
        if info.kind != HOLE and info.color != ACTION_COLORS[ERASER]:
          return some(info)
    for child in thing.things.value:
      if child of Build:
        let build = Build(child)
        let local_pos = position.local_into(build)
        if local_pos in build:
          let info = build.voxel_info(local_pos)
          if info.kind != HOLE and info.color != ACTION_COLORS[ERASER]:
            return some(info)
  none(VoxelInfo)

proc has_block_at(position: Vector3): bool =
  find_block_at(position).is_some

proc rendered_voxel_count_get(self: Build): int =
  ## Total voxels the build_node has painted into the terrain, across
  ## every render path: the on_block_loaded snapshot/delta paste, the
  ## watch_delta_seq deltas to already-loaded chunks, and the ASAP
  ## buffer. Diagnostic for catching dropped writes; lags the model
  ## count while paints are still catching up. May slightly over-count
  ## if a delta is re-pasted (idempotent), so compare with `>=`.
  self.rendered_voxel_count

proc pending_block_updates_get(self: Thing): int =
  ## Unfinished voxel pipeline work for the thing and all of its
  ## descendants: worker-side chunks/edits not yet flushed to the render
  ## thread, plus the terrain backlog (queued, in-flight, or awaiting
  ## apply) as last pushed from the nodes. 0 = every submitted edit is
  ## meshed and visible.
  result = self.pending_block_updates
  if self of Build and ?Build(self).voxels:
    let voxels = Build(self).voxels
    result += voxels.pending_chunks.len + voxels.pending_edits.len
  for child in self.things.value:
    result += child.pending_block_updates_get

type WorldBox* = tuple[min, max: Vector3]

proc get_WorldBox(a: VmArgs, pos: int): WorldBox =
  # The VM passes WorldBox as nkPar( nkPar(min.x,y,z), nkPar(max.x,y,z) ).
  let node = a.get_node(pos)
  let lo = node.sons[0].sons
  let hi = node.sons[1].sons
  result = (
    vec3(lo[0].float_val, lo[1].float_val, lo[2].float_val),
    vec3(hi[0].float_val, hi[1].float_val, hi[2].float_val),
  )

proc tight_voxel_aabb(self: Build): tuple[present: bool, lo, hi: Vector3] =
  ## Voxel-tight local-space AABB of the build's visible voxels.
  ## `present` is false if the build has no visible voxels.
  var lo = vec3(float.high, float.high, float.high)
  var hi = vec3(-float.high, -float.high, -float.high)
  var any_voxel = false
  for (pos, info) in self.voxels.all_voxels:
    if info.kind == HOLE or info.color == ACTION_COLORS[ERASER]:
      continue
    any_voxel = true
    if pos.x < lo.x: lo.x = pos.x
    if pos.y < lo.y: lo.y = pos.y
    if pos.z < lo.z: lo.z = pos.z
    if pos.x + 1.0 > hi.x: hi.x = pos.x + 1.0
    if pos.y + 1.0 > hi.y: hi.y = pos.y + 1.0
    if pos.z + 1.0 > hi.z: hi.z = pos.z + 1.0
  (any_voxel, lo, hi)

proc world_aabb(thing: Thing, lo, hi: Vector3): WorldBox =
  # Transform all 8 corners of the local-space AABB through the
  # thing's own transform, then walk the parent chain accumulating
  # parent origins (mirroring `global_from` / the position getter).
  # Re-fit to an axis-aligned box at the end.
  var w_lo = vec3(float.high, float.high, float.high)
  var w_hi = vec3(-float.high, -float.high, -float.high)
  let t = thing.transform
  for cx in [lo.x, hi.x]:
    for cy in [lo.y, hi.y]:
      for cz in [lo.z, hi.z]:
        var p = t.basis.xform(vec3(cx, cy, cz)) + t.origin
        var parent = thing.parent
        while parent != nil:
          p += parent.transform.origin
          parent = parent.parent
        if p.x < w_lo.x: w_lo.x = p.x
        if p.y < w_lo.y: w_lo.y = p.y
        if p.z < w_lo.z: w_lo.z = p.z
        if p.x > w_hi.x: w_hi.x = p.x
        if p.y > w_hi.y: w_hi.y = p.y
        if p.z > w_hi.z: w_hi.z = p.z
  (w_lo, w_hi)

proc bounds(self: Thing): WorldBox =
  ## Tight world-space AABB after scale/rotation/anchor are applied.
  ## Builds report the bounding box of placed voxels. Bots/players
  ## fall back to a small box around `position` (collider-aware
  ## bounds is a follow-up).
  if self of Build:
    let b = Build(self)
    let (present, lo, hi) = b.tight_voxel_aabb
    if not present:
      let p = b.position
      return (p, p)
    return world_aabb(b, lo, hi)
  else:
    let p = self.position
    (p - vec3(0.5, 0.0, 0.5), p + vec3(0.5, 1.5, 0.5))

proc bounds_at(
    self: Build, position: Vector3, rotation: float = 0.0, scale: float = 0.0
): WorldBox =
  ## Predict the world AABB of a hypothetical instance of this proto
  ## at the given pose. Lets scripts validate `.new(position = ...)`
  ## before committing — e.g. `if box_is_free(DiningChair.bounds_at(
  ## vec3(4, 1, -103), rotation = 90)): DiningChair.new(...)`.
  ##
  ## Matches `.new()`'s "0 means proto default" sentinel for scale
  ## and rotation: pass non-zero to override.
  ##
  ## Composes the anchor offset the same way Bot/Build init does:
  ## visible pose = T_anchor; voxel transform = T_anchor * inverse(A),
  ## so a voxel at local coord v lands at
  ##   T_anchor.basis * (v - A.origin) + position.
  ##
  ## Limitation: reads the proto's *actual* voxel data. Legacy protos
  ## that use the `if not is_instance: quit()` early-out never draw,
  ## so their bounds_at reports only the default 1x1x1 starter block.
  ## Drop the early-quit so the proto's draw runs against itself too.
  let (present, lo, hi) = self.tight_voxel_aabb
  if not present:
    return (position, position)
  let
    effective_scale = if scale > 0.0: scale else: self.scale
    effective_scale_safe =
      if effective_scale > 0.0: effective_scale else: 1.0
  var basis = init_basis()
  if effective_scale_safe != 1.0:
    basis = basis.scaled(
      vec3(effective_scale_safe, effective_scale_safe, effective_scale_safe)
    )
  if rotation != 0.0:
    basis = basis.rotated(UP, deg_to_rad(rotation).float32)
  let
    a = self.anchor
    voxel_basis = basis * a.basis.inverse
    voxel_origin = position - basis.xform(a.origin)
  var w_lo = vec3(float.high, float.high, float.high)
  var w_hi = vec3(-float.high, -float.high, -float.high)
  for cx in [lo.x, hi.x]:
    for cy in [lo.y, hi.y]:
      for cz in [lo.z, hi.z]:
        let p = voxel_basis.xform(vec3(cx, cy, cz)) + voxel_origin
        if p.x < w_lo.x: w_lo.x = p.x
        if p.y < w_lo.y: w_lo.y = p.y
        if p.z < w_lo.z: w_lo.z = p.z
        if p.x > w_hi.x: w_hi.x = p.x
        if p.y > w_hi.y: w_hi.y = p.y
        if p.z > w_hi.z: w_hi.z = p.z
  (w_lo, w_hi)

proc box_intersects(a, b: WorldBox): bool {.inline.} =
  # Half-open overlap test ([min, max)): boxes that merely share a boundary
  # plane (a.max == b.min) do NOT overlap. Using strict `<`/`>` here counted
  # touching as intersecting, so a single-voxel `clear_box` query reported
  # "occupied" whenever an adjacent cell held a voxel.
  not (
    a.max.x <= b.min.x or a.min.x >= b.max.x or a.max.y <= b.min.y or
    a.min.y >= b.max.y or a.max.z <= b.min.z or a.min.z >= b.max.z
  )

proc world_offset(thing: Thing): Vector3 =
  # Sum parent origins so per-voxel coords resolve to world space,
  # mirroring `global_from` / `world_aabb`. Used by the query API to
  # walk voxels in world coordinates without re-traversing the thing
  # tree for each lookup.
  var p = thing.parent
  while p != nil:
    result += p.transform.origin
    p = p.parent

proc voxel_overlaps(a: Build, b: Build): bool =
  # True if any visible voxel of `a` falls inside a visible voxel of
  # `b` (and vice versa). Iterates `a`'s voxels, projects each into
  # `b`'s local coords, and looks up. Cost scales with `a`'s voxel
  # count; pick the smaller build as `a` when both extents are big.
  let
    ta = a.transform
    offset_a = a.world_offset
    tb = b.transform
    offset_b = b.world_offset
    tb_basis_inv = tb.basis.inverse
    b_origin_world = tb.origin + offset_b
  for (pos, info) in a.voxels.all_voxels:
    if info.kind == HOLE or info.color == ACTION_COLORS[ERASER]:
      continue
    # World position of `a`'s voxel centre.
    let world = ta.basis.xform(pos + vec3(0.5, 0.5, 0.5)) + ta.origin + offset_a
    # Translate into `b`'s local frame, then floor to voxel coords.
    let in_b_local = tb_basis_inv.xform(world - b_origin_world)
    let cell = vec3(in_b_local.x.floor, in_b_local.y.floor, in_b_local.z.floor)
    if cell in b:
      let info_b = b.voxel_info(cell)
      if info_b.kind != HOLE and info_b.color != ACTION_COLORS[ERASER]:
        return true
  false

proc overlaps(a: Thing, b: Thing): bool =
  ## True if the two things' geometry actually overlaps. AABBs are
  ## checked first as a cheap reject; for two Builds we then test
  ## whether any of `a`'s voxels falls inside one of `b`'s, which
  ## handles the "furniture inside a hollow room" case correctly
  ## (the room's AABB fills the interior but its voxels are only
  ## the walls). For Bot/Player pairs the AABB result stands —
  ## their bounds are already a tight capsule approximation.
  if not box_intersects(a.bounds, b.bounds):
    return false
  if a of Build and b of Build:
    return voxel_overlaps(Build(a), Build(b))
  true

proc things_overlapping(box: WorldBox): seq[Thing] =
  ## Things (root + nested) whose world-space bounds intersect `box`.
  proc walk(thing: Thing, out_things: var seq[Thing]) =
    if box_intersects(thing.bounds, box):
      out_things.add(thing)
    for c in thing.things.value:
      walk(c, out_things)
  for u in state.things.value:
    walk(u, result)

proc voxels_in_box*(box: WorldBox): bool =
  ## True if any visible voxel (any Build's data) intersects `box`.
  ## Walks only builds whose own bounds overlap the query, then tests
  ## each of those builds' voxels — cost scales with the voxel count
  ## of nearby builds, not with the query volume.
  proc walk(thing: Thing): bool =
    if thing of Build:
      let build = Build(thing)
      # Explicit Thing() so we dispatch through the WorldBox-returning
      # `bounds` above, not Build's local-AABB field accessor.
      if box_intersects(Thing(build).bounds, box):
        let
          t = build.transform
          offset = build.world_offset
        for (pos, info) in build.voxels.all_voxels:
          if info.kind == HOLE or info.color == ACTION_COLORS[ERASER]:
            continue
          let
            a = t.basis.xform(pos) + t.origin + offset
            b = t.basis.xform(pos + vec3(1, 1, 1)) + t.origin + offset
            vlo = vec3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
            vhi = vec3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
          if box_intersects((vlo, vhi), box):
            return true
    for c in thing.things.value:
      if walk(c): return true
    false

  for u in state.things.value:
    if walk(u): return true
  false

proc box_is_free(box: WorldBox): bool =
  ## True if `box` is free of voxels (any Build's voxel data) AND
  ## doesn't intersect any thing's bounds. Use to validate a proposed
  ## placement. Contrast with `clear_box`, which only checks voxels.
  if voxels_in_box(box):
    return false
  for u in state.things.value:
    if box_intersects(u.bounds, box):
      return false
  true

proc things_in_box(
    x1: float, y1: float, z1: float, x2: float, y2: float, z2: float
): seq[Thing] =
  ## Things whose origins are inside the inclusive world-space box.
  ## For "is this thing's body in the box," use `things_overlapping`.
  let lo = vec3(min(x1, x2), min(y1, y2), min(z1, z2))
  let hi = vec3(max(x1, x2), max(y1, y2), max(z1, z2))
  proc walk(thing: Thing, out_things: var seq[Thing]) =
    let p = thing.position
    if p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and
        p.z >= lo.z and p.z <= hi.z:
      out_things.add(thing)
    for c in thing.things.value:
      walk(c, out_things)
  for u in state.things.value:
    walk(u, result)

proc top_local_world_y(build: Build, x, z: float): Option[int] =
  ## The world y of the highest visible voxel in `build`'s column under
  ## world (x, z), or none. Scans the build's OWN local column so scaled
  ## builds report the right height — a world-y scan steps whole world
  ## units and skips a scaled build's layers (spaced `scale` apart). The
  ## local x,z are sampled at the ground (rotated builds are approximate;
  ## for the common axis-aligned + scaled case it's exact).
  let ground = vec3(floor(x), 0, floor(z)).local_into(build)
  let lx = floor(ground.x)
  let lz = floor(ground.z)
  # Local range generous enough to cover the world -32..64 span at scales
  # down to ~0.25; first hit from the top is the surface.
  for ly in countdown(256, -128):
    let lpos = vec3(lx, ly.float, lz)
    if lpos in build:
      let info = build.voxel_info(lpos)
      if info.kind != HOLE and info.color != ACTION_COLORS[ERASER]:
        return some(floor(lpos.world_from(build).y).int)

proc floor_at(x: float, z: float): int =
  ## Return the highest world y at (x, z) that has a visible voxel, or -1 if
  ## the column is empty. Useful for "where should I place this on the
  ## ground". Correct for scaled builds (see top_local_world_y).
  var top = low(int)
  for unit in state.things.value:
    if unit of Build:
      let hit = top_local_world_y(Build(unit), x, z)
      if hit.is_some:
        top = max(top, hit.get)
    for child in unit.things.value:
      if child of Build:
        let hit = top_local_world_y(Build(child), x, z)
        if hit.is_some:
          top = max(top, hit.get)
  result = if top == low(int): -1 else: top

proc clear_box(
    x1: float, y1: float, z1: float, x2: float, y2: float, z2: float
): bool =
  ## True if no visible voxel exists anywhere inside the inclusive box
  ## (snapped to the voxel grid). Use before placing a new structure to
  ## confirm the volume is empty.
  let
    lo = vec3(floor(min(x1, x2)), floor(min(y1, y2)), floor(min(z1, z2)))
    # +1 to make the inclusive voxel box a half-open float box matching
    # what `voxels_in_box` expects.
    hi = vec3(
      floor(max(x1, x2)) + 1, floor(max(y1, y2)) + 1, floor(max(z1, z2)) + 1
    )
  not voxels_in_box((lo, hi))

proc find_voxel_overlaps(limit: int = 50): string =
  ## Find world positions where two or more Builds both have a visible
  ## (non-HOLE, non-eraser) voxel — i.e., actual z-fighting in the
  ## rendered scene. Returns one line per overlap up to `limit`.
  var occupants = init_table[Vector3, seq[string]]()
  proc collect(thing: Thing) =
    if thing of Build:
      let build = Build(thing)
      # Skip scaled/rotated builds — their voxel-to-world mapping isn't a
      # simple translation and overlap reports would be misleading.
      let euler = build.transform.basis.get_euler()
      let basis_is_identity =
        abs(euler.x) < 0.001 and abs(euler.y) < 0.001 and abs(euler.z) < 0.001
      let scale_is_one = abs(build.scale - 1.0) < 0.001
      if basis_is_identity and scale_is_one:
        for (local_pos, info) in build.voxels.all_voxels:
          if info.kind == HOLE or info.color == ACTION_COLORS[ERASER]:
            continue
          let global_pos = local_pos.global_from(build)
          if global_pos notin occupants:
            occupants[global_pos] = @[]
          if build.id notin occupants[global_pos]:
            occupants[global_pos].add(build.id)
    for child in thing.things.value:
      collect(child)
  for thing in state.things.value:
    collect(thing)
  var n = 0
  for pos, ids in occupants:
    if ids.len < 2: continue
    result &=
      "(" & $pos.x & "," & $pos.y & "," & $pos.z & ") " & ids.join(" + ") & "\n"
    n.inc
    if n >= limit:
      result &= "... (truncated at " & $limit & ")\n"
      return

proc block_color_at(position: Vector3): Color =
  let block_info = find_block_at(position)
  if block_info.is_some:
    block_info.get.color
  else:
    ACTION_COLORS[ERASER]

proc count_draw(self: Build) =
  ## Cooperative pacing for the immediate drawing APIs. The logo APIs yield
  ## naturally (they animate in-engine); the immediate ones do all their work
  ## inside the bridged call, so a build script could otherwise run its whole
  ## control flow in one unyielding resume. Pause every draw_yield_interval
  ## calls: the VMPause fires on the next VM instruction (after this call
  ## returns), the script resumes next tick with a fresh fuel budget — so no
  ## legitimate drawing script can exhaust the watchdog, regardless of size.
  if ?self.script_ctx:
    inc self.script_ctx.unyielded_draws
    if self.script_ctx.unyielded_draws >= draw_yield_interval:
      self.script_ctx.unyielded_draws = 0
      self.script_ctx.pause()

proc draw_voxel(self: Build, position: Vector3, color: Color) =
  ## Paint a TRANSIENT voxel. Goes through Build.draw, which only writes to
  ## local_voxels (not local_edits), so the block is regenerated when the
  ## script reloads and isn't bloating the save file. Backs place.
  self.count_draw
  let info: VoxelInfo = (TRANSIENT, color)
  self.draw(position, info)

const
  BOX_PIVOT_CORNER = 0
  BOX_PIVOT_CENTRE = 1
  BOX_PIVOT_BOTTOM_CENTRE = 2

proc box_local_bounds(
    w, h, d: int, pivot: int, use_turtle: bool
): tuple[lo, hi: Vector3] =
  ## Returns the box's continuous bounds in basis-local coords, given
  ## width / height / depth (voxel counts, all positive) and a pivot
  ## constant.
  ##
  ## Width extends along +X and height along +Y in both modes. Depth
  ## direction differs:
  ##   - turtle mode: depth extends along -Z (the turtle's forward),
  ##     so `forward N; back N` and `box(_, _, N)` cover the same
  ##     voxels.
  ##   - `at = vec3(...)` mode: depth extends along +Z so `at` reads
  ##     as the minimum-coord corner of the box. Without this, an
  ##     axis-aligned `box(at = vec3(x, y, z), depth = N)` would
  ##     silently extend into negative Z from `at`, which is
  ##     counterintuitive for script-coords work.
  ##
  ## For even dimensions with non-corner pivots, the half-voxel snaps
  ## to the negative side (one extra voxel toward the back-bottom-
  ## left) so the convention matches the corner pivot's
  ## back-bottom-left intuition.
  let z_sign = if use_turtle: -1.0 else: 1.0
  case pivot
  of BOX_PIVOT_CORNER:
    let z_far = z_sign * (d - 1).float
    result.lo = vec3(0.0, 0.0, min(0.0, z_far))
    result.hi = vec3((w - 1).float, (h - 1).float, max(0.0, z_far))
  of BOX_PIVOT_CENTRE:
    let x_lo = -(w div 2).float
    let y_lo = -(h div 2).float
    let z_centre_high = (d div 2).float - (if d mod 2 == 0: 1.0 else: 0.0)
    let z_hi_t = z_centre_high
    let z_lo_t = z_centre_high - (d - 1).float
    let (z_lo, z_hi) =
      if use_turtle: (z_lo_t, z_hi_t)
      else: (-z_hi_t, -z_lo_t)
    result.lo = vec3(x_lo, y_lo, z_lo)
    result.hi = vec3(x_lo + (w - 1).float, y_lo + (h - 1).float, z_hi)
  of BOX_PIVOT_BOTTOM_CENTRE:
    let x_lo = -(w div 2).float
    let z_centre_high = (d div 2).float - (if d mod 2 == 0: 1.0 else: 0.0)
    let z_hi_t = z_centre_high
    let z_lo_t = z_centre_high - (d - 1).float
    let (z_lo, z_hi) =
      if use_turtle: (z_lo_t, z_hi_t)
      else: (-z_hi_t, -z_lo_t)
    result.lo = vec3(x_lo, 0.0, z_lo)
    result.hi = vec3(x_lo + (w - 1).float, (h - 1).float, z_hi)
  else:
    result.lo = vec3(0.0, 0.0, 0.0)
    result.hi = vec3(0.0, 0.0, 0.0)

proc box_impl(
    self: Build,
    w: int,
    h: int,
    d: int,
    color: Color,
    fill: bool,
    pivot: int,
    at: Vector3,
    rotation_deg: float,
    use_turtle: bool,
) =
  ## OBB scan-converter. Walks the world-AABB of the box, inverse-
  ## transforms each voxel into box-local coords, draws it if it lies
  ## inside the box's per-pivot bounds.
  if w <= 0 or h <= 0 or d <= 0:
    return
  self.count_draw

  var basis: Basis
  var origin: Vector3
  if use_turtle:
    basis = self.draw_transform.basis
    origin = self.draw_transform.origin
  else:
    basis = init_basis()
    if rotation_deg != 0.0:
      basis = basis.rotated(UP, deg_to_rad(rotation_deg).float32)
    origin = at

  let (lo, hi) = box_local_bounds(w, h, d, pivot, use_turtle)

  # World-AABB from the 8 OBB corners.
  var u_lo = vec3(float.high, float.high, float.high)
  var u_hi = vec3(float.low, float.low, float.low)
  for cx in [lo.x, hi.x]:
    for cy in [lo.y, hi.y]:
      for cz in [lo.z, hi.z]:
        let p = basis.xform(vec3(cx, cy, cz)) + origin
        u_lo.x = min(u_lo.x, p.x)
        u_lo.y = min(u_lo.y, p.y)
        u_lo.z = min(u_lo.z, p.z)
        u_hi.x = max(u_hi.x, p.x)
        u_hi.y = max(u_hi.y, p.y)
        u_hi.z = max(u_hi.z, p.z)

  let ix_lo = u_lo.x.floor.int
  let iy_lo = u_lo.y.floor.int
  let iz_lo = u_lo.z.floor.int
  let ix_hi = u_hi.x.ceil.int
  let iy_hi = u_hi.y.ceil.int
  let iz_hi = u_hi.z.ceil.int

  let info: VoxelInfo = (TRANSIENT, color)
  # 0.5 = half-voxel inclusion threshold. For axis-aligned cases this
  # is a no-op (voxel centres land exactly on integer coords, the
  # extra 0.5 margin doesn't add any cells). For off-axis cases it
  # gives the "fat" Bresenham-style rasterisation that matches what
  # `forward N` at non-cardinal headings already produces — a
  # 1-thick wall at 45° draws a 1-voxel-wide stairstep instead of
  # leaving holes between integer grid points.
  let pad = 0.5
  for ix in ix_lo .. ix_hi:
    for iy in iy_lo .. iy_hi:
      for iz in iz_lo .. iz_hi:
        let world = vec3(ix.float, iy.float, iz.float)
        let local = basis.xform_inv(world - origin)
        if local.x < lo.x - pad or local.x > hi.x + pad:
          continue
        if local.y < lo.y - pad or local.y > hi.y + pad:
          continue
        if local.z < lo.z - pad or local.z > hi.z + pad:
          continue
        if not fill:
          let near = min(
            min(local.x - lo.x, hi.x - local.x),
            min(min(local.y - lo.y, hi.y - local.y),
                min(local.z - lo.z, hi.z - local.z)),
          )
          if near > 0.5:
            continue
        self.draw(world, info)

proc sphere_impl(
    self: Build,
    size: float,
    color: Color,
    fill: bool,
    at: Vector3,
    use_turtle: bool,
) =
  ## Radially-symmetric, so basis doesn't matter — only the centre.
  ## `size` = diameter in voxels (fractional sizes give finer-grained
  ## tapers, e.g. stacked-disk cones). Radius = size / 2.
  if size <= 0.0:
    return
  self.count_draw
  let centre = if use_turtle: self.draw_transform.origin else: at
  let radius = size / 2.0
  let r_int = (radius + 0.5).floor.int
  let info: VoxelInfo = (TRANSIENT, color)
  for dx in -r_int .. r_int:
    for dy in -r_int .. r_int:
      for dz in -r_int .. r_int:
        let dist = sqrt((dx * dx + dy * dy + dz * dz).float)
        if dist > radius:
          continue
        if not fill and dist < radius - 1.0:
          continue
        let p = centre + vec3(dx.float, dy.float, dz.float)
        self.draw(vec3(p.x.round, p.y.round, p.z.round), info)

proc cylinder_impl(
    self: Build,
    size: float,
    height: int,
    color: Color,
    fill: bool,
    at: Vector3,
    use_turtle: bool,
) =
  ## Axis = turtle's local up. Pivot = centre of the bottom face.
  ## `size` = diameter in voxels (fractional sizes give finer-grained
  ## tapers), `height` = voxels along the axis.
  if size <= 0.0 or height <= 0:
    return
  self.count_draw

  var basis: Basis
  var origin: Vector3
  if use_turtle:
    basis = self.draw_transform.basis
    origin = self.draw_transform.origin
  else:
    basis = init_basis()
    origin = at

  let radius = size / 2.0
  let r_int = (radius + 0.5).floor.int

  # Bounds in cylinder-local coords for the AABB seed.
  let lo = vec3(-r_int.float, 0.0, -r_int.float)
  let hi = vec3(r_int.float, (height - 1).float, r_int.float)

  var u_lo = vec3(float.high, float.high, float.high)
  var u_hi = vec3(float.low, float.low, float.low)
  for cx in [lo.x, hi.x]:
    for cy in [lo.y, hi.y]:
      for cz in [lo.z, hi.z]:
        let p = basis.xform(vec3(cx, cy, cz)) + origin
        u_lo.x = min(u_lo.x, p.x)
        u_lo.y = min(u_lo.y, p.y)
        u_lo.z = min(u_lo.z, p.z)
        u_hi.x = max(u_hi.x, p.x)
        u_hi.y = max(u_hi.y, p.y)
        u_hi.z = max(u_hi.z, p.z)

  let ix_lo = u_lo.x.floor.int
  let iy_lo = u_lo.y.floor.int
  let iz_lo = u_lo.z.floor.int
  let ix_hi = u_hi.x.ceil.int
  let iy_hi = u_hi.y.ceil.int
  let iz_hi = u_hi.z.ceil.int

  let info: VoxelInfo = (TRANSIENT, color)
  for ix in ix_lo .. ix_hi:
    for iy in iy_lo .. iy_hi:
      for iz in iz_lo .. iz_hi:
        let world = vec3(ix.float, iy.float, iz.float)
        let local = basis.xform_inv(world - origin)
        let r2 = local.x * local.x + local.z * local.z
        if r2 > radius * radius:
          continue
        if local.y < -0.5 or local.y > (height - 1).float + 0.5:
          continue
        if not fill and r2 < (radius - 1.0) * (radius - 1.0):
          continue
        self.draw(world, info)

proc place_block(self: Build, position: Vector3, color: Color) =
  ## Place a persistent PERSISTED voxel. The block is saved to local_edits and
  ## survives reload. For programmatic block-placement use draw_voxel.
  let info: VoxelInfo = (PERSISTED, color)
  self.add_voxel(position, info)
  self.voxels.set_edit(position, info)
  self.global_flags += DIRTY # hand-style edit: persist on the next save

proc sealed_frames(self: Build): bool =
  self.sealed_frames

proc sealed_frames_set(self: Build, value: bool) =
  self.sealed_frames = value
  self.global_flags += DIRTY

proc cull_down_faces(self: Build): bool =
  self.cull_down_faces

proc cull_down_faces_set(self: Build, value: bool) =
  self.cull_down_faces = value
  self.global_flags += DIRTY

proc frames_len(self: Build): int =
  self.frame_count

proc save_frame_impl(self: Build, at: int): int =
  self.save(at)

proc play_impl(self: Build, fps: float, loop: bool) =
  self.play(fps, loop)

proc stop_impl(self: Build) =
  self.stop()

proc frame(self: Build): int =
  self.current_frame

proc `frame=`(self: Build, index: int) =
  self.current_frame = index
  self.global_flags += DIRTY # the displayed frame persists

proc save_level_now() =
  serializers.save_level(state.config.level_dir, force = true)

proc reload_thing(self: Build) =
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
    pending_block_updates_get,
    exec_instance, capture_start_transform, hit, exit, global, `global=`,
    position, local_position,
    rotation, `rotation=`, id, glow, `glow=`, speed, `speed=`, scale, `scale=`,
    velocity, `velocity=`, active_thing, color, `color=`, sees, start_position,
    wake, frame_count, write_stack_trace, show, `show=`, frame_created, lock,
    `lock=`, reset, press_action, release_action, load_level, level_name,
    world_name,
    reset_level, current_colliders, added_things, all_players, all_builds,
    all_bots, all_signs, all_things, signal_test_complete, now_seconds,
    dump_stats, find_voxel_overlaps, things_in_box, floor_at, clear_box, bounds,
    overlaps, things_overlapping, box_is_free, bounds_at, adopt, release

  result.bridged_from_vm "base_bridge_private",
    action_running, `action_running=`, yield_script, begin_turn, begin_move,
    sleep_impl, position_set, start_position_set, reset_anchor, delete,
    keep_alive, new_markdown_sign, update_markdown_sign, claim_name

  result.bridged_from_vm "bots", play

  result.bridged_from_vm "builds",
    drawing, `drawing=`, initial_position, pen, pen_set, draw_position,
    draw_position_set, has_block_at, block_color_at, begin_asap, end_asap,
    draw_voxel, save_level_now, reload_thing, box_impl, sphere_impl,
    cylinder_impl, advance, rendered_voxel_count_get, pending_block_updates_get,
    save_frame_impl, load_frame, delete_frame, clear_frames, frame,
    `frame=`, frames_len, play_impl, stop_impl, cull_down_faces,
    cull_down_faces_set, sealed_frames, sealed_frames_set

  result.bridged_from_vm "builds_private", place_block

  result.bridged_from_vm "signs",
    message, `message=`, more, `more=`, height, `height=`, width, `width=`,
    size, `size=`, open, `open=`, billboard, `billboard=`

  result.bridged_from_vm "players",
    playing, `playing=`, god, `god=`, flying, `flying=`, tool, `tool=`,
    tools_has, tools_incl, tools_excl, tools_clear, coding,
    `coding=`, running, `running=`, open_sign, `open_sign=`, executing_player,
    block_log, clear_block_log

  result.bridged_from_vm "worlds",
    environment, `environment=`, megapixels, `megapixels=`
