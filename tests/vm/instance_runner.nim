## Headless smoke test for Enu's script-loading + instancing path.
##
## Loads a small test world (protos + spawner + plain Builds) through
## Enu's real script-loading flow: `build_code_template` generates the
## wrapper, `ctx.load`/`ctx.run` drives the Nim VM, `enter_hook` does
## the suspend/resume dance, and `exec_instance` re-enters the VM via
## `call_routine` exactly like production.
##
## What's mocked vs. what's real:
##   - real:   Nim VM, vmlib/enu, ScriptCtx, Interpreter,
##             build_code_template, load_enu_script macro, enter_hook,
##             sleep -> VMPause, ctx.resume(), genProc cache,
##             re-entrant rawExecute via call_routine.
##   - mocked: Unit/PNode mapping (just an active-id stack), Godot,
##             voxels, colliders, IO. Mocks are stubs that don't
##             allocate or touch state.
##
## History: was originally meant to reproduce the IndexDefect from
## heavy-instancing production worlds. Turned out the defect this
## test produced was a test-harness bug (exec_instance mock was
## routing every clone to the first proto's `run_script`, which fed
## the wrong type into the VM and tripped `opcLdObj` past the object's
## field count). Real production routing uses
## `ScriptCtx.module_name = clone_of.id`. After fixing the mock to
## infer the clone's module from `dest.typ.sym.owner`, the test
## runs clean: 120 nested `.new` calls + 125 VMPause/resume cycles +
## 2.1M VM instructions, max re-entry depth 2.
##
## Run via `nim instance_tests`.

{.push warning[GcUnsafe2]: off.}

import std/[os, strutils, sets, sequtils, monotimes, algorithm]
import core
import libs/[interpreters, eval]
import pkg/compiler/[vm, ast, lineinfos, vmdef]

include "../../src/models/build_code_template.nim.nimf"

private_access ScriptCtx

const
  TestWorldDir = "tests/vm/test_world"
  ScriptsSubdir = "scripts"
  GeneratedSubdir = "generated"

type
  ContextKind = enum
    SCRIPT
    CLONE

  ManagedCtx = ref object
    kind: ContextKind
    ctx: ScriptCtx
    label: string
    unit_id: string
    finished: bool

  Runner = object
    interp: Interpreter
    new_instance_calls: int
    exec_instance_calls: int
    sleep_calls: int
    resume_calls: int
    instr_count: int

    # Each host-driven VM entry (ctx.run, ctx.resume, exec_instance's
    # call_routine) increments depth. Production's hack lets these nest:
    # a host bridge invoked from inside one rawExecute can call back into
    # rawExecute via call_routine. depth > 1 = re-entrant.
    depth: int
    max_depth: int
    # Events that fire so we can correlate the defect with depth.
    event_log: seq[string]

    # Stack of currently-executing contexts. The top determines what
    # `active_unit().id` returns to the VM.
    active_stack: seq[ManagedCtx]
    paused: seq[ManagedCtx]

    # All scripts in the synthetic world. Used to compute the auto-import
    # list for each wrapper.
    all_units: seq[string]
    proto_modules: HashSet[string]

var runner: Runner

proc log_event(s: string) =
  runner.event_log.add s

template enter_vm(label: string, body: untyped): untyped =
  inc runner.depth
  if runner.depth > runner.max_depth: runner.max_depth = runner.depth
  log_event "ENTER d=" & $runner.depth & " " & label
  try:
    body
  finally:
    log_event "EXIT  d=" & $runner.depth & " " & label
    dec runner.depth

proc current_ctx(): ScriptCtx =
  if runner.active_stack.len > 0:
    runner.active_stack[^1].ctx
  else:
    nil

proc current_unit_id(): string =
  if runner.active_stack.len > 0:
    runner.active_stack[^1].unit_id
  else:
    ""

proc enter_hook(c: PCtx, pc: int, tos: PStackFrame, instr: TInstr) =
  ## Mirrors scripting.nim:130 — save VM frame state into the active
  ## ScriptCtx every instruction so resume() has somewhere to pick up.
  let ctx = current_ctx()
  if ctx == nil:
    return
  ctx.ctx = c
  ctx.pc = pc
  ctx.tos = tos
  inc runner.instr_count
  if ctx.pause_requested:
    ctx.pause_requested = false
    raise VMPause.new_exception("vm paused")

proc setup_mocks(interp: Interpreter, vmlib_path: string)

proc setup_mocks(interp: Interpreter, vmlib_path: string) =
  const pkg = "enu"

  interp.register_error_hook proc(
      config, info, msg, severity: auto
  ) {.gcsafe.} =
    if severity == Severity.Error:
      echo "  [VM ERROR] ", msg

  interp.enter_hook = enter_hook

  # rawExecute defer fires this on every exit (normal return AND
  # exception unwind). Production's enterHook is the only place pc/tos
  # gets saved; we use this to spot when a rawExecute unwinds without
  # the caller noticing.
  interp.exit_hook = proc(c: PCtx, pc: int, tos: PStackFrame) =
    {.cast(gcsafe).}:
      log_event "rawExecute EXIT d=" & $runner.depth

  # The class_macros' load_enu_script invokes read_enu_script at macro
  # expansion time to read the user's actual script. Production overrides
  # it via implement_routine (host_bridge.nim:713-731); without that, the
  # VM falls back to slurp/static_read which it doesn't support. Same
  # path-resolution rules: relative names resolve under scripts/.
  interp.implement_routine pkg, "base_bridge_private", "read_enu_script",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        let filename = args.get_string(0)
        let full_path =
          if filename.is_absolute:
            filename
          elif filename.starts_with("../" & ScriptsSubdir):
            TestWorldDir / filename[3 ..^ 1]
          else:
            TestWorldDir / ScriptsSubdir / filename
        let normalized = full_path.replace("\\", "/").normalized_path
        args.set_result(read_file(normalized))

  interp.implement_routine pkg, "base_bridge", "echo_console_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        echo "  [VM] ", args.get_string(0)

  interp.implement_routine pkg, "base_bridge", "frame_count_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(1))

  # The macro guard does `active_unit().id == script_id`. We override
  # id_impl to ignore the input PNode and always return whichever unit_id
  # is currently active in the runner's stack — this keeps the guard
  # correct without us having to maintain a real PNode -> Unit table.
  interp.implement_routine pkg, "base_bridge", "id_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        args.set_result(current_unit_id())

  # sleep / yield: request a pause. enter_hook turns it into VMPause.
  interp.implement_routine pkg, "base_bridge_private", "sleep_impl_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        inc runner.sleep_calls
        let ctx = current_ctx()
        if ctx != nil:
          ctx.pause_requested = true

  interp.implement_routine pkg, "base_bridge_private", "yield_script_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        let ctx = current_ctx()
        if ctx != nil:
          ctx.pause_requested = true

  interp.implement_routine pkg, "base_bridge_private", "action_running_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(0))
  interp.implement_routine pkg,
    "base_bridge_private",
    "action_running_set_impl",
    proc(args: VmArgs) = discard
  interp.implement_routine pkg, "base_bridge", "write_stack_trace_impl",
    proc(args: VmArgs) = discard
  interp.implement_routine pkg, "base_bridge", "exit_impl",
    proc(args: VmArgs) = discard
  interp.implement_routine pkg, "base_bridge", "register_template_node_impl",
    proc(args: VmArgs) = discard
  interp.implement_routine pkg, "base_bridge", "signal_test_complete_impl",
    proc(args: VmArgs) = discard
  interp.implement_routine pkg, "builds", "has_block_at_impl",
    proc(args: VmArgs) = args.set_result(false)
  interp.implement_routine pkg, "builds", "block_color_at_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(0))
  for sink in [
    "place_block_impl", "save_level_now_impl", "reload_unit_impl",
    "begin_asap_impl", "end_asap_impl", "box_impl_impl",
    "sphere_impl_impl", "cylinder_impl_impl", "draw_voxel_impl",
    "advance_impl",
  ]:
    interp.implement_routine pkg, "builds", sink,
      proc(args: VmArgs) = discard
  interp.implement_routine pkg, "builds", "rendered_voxel_count_get_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(0))
  interp.implement_routine pkg, "builds", "drawing_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(1))
  interp.implement_routine pkg, "builds", "initial_position_impl",
    proc(args: VmArgs) =
      var v = nkTupleConstr.new_tree
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      args.set_result(v)
  interp.implement_routine pkg, "builds", "draw_position_impl",
    proc(args: VmArgs) =
      var v = nkTupleConstr.new_tree
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      args.set_result(v)

  interp.implement_routine pkg, "vm_bridge_utils", "get_last_error_impl",
    proc(args: VmArgs) =
      var n = nkTupleConstr.new_tree
      n.add new_int_node(nkIntLit, 0)
      n.add new_str_node(nkStrLit, "")
      args.set_result(n)

  var test_time = 0.0
  interp.implement_routine pkg, "base_bridge", "now_seconds_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        test_time += 0.001
        args.set_result(test_time)

  interp.implement_routine pkg, "base_bridge", "local_position_impl",
    proc(args: VmArgs) =
      var v = nkTupleConstr.new_tree
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      args.set_result(v)

  for sink in [
    "wake_impl",
    "capture_start_transform_impl",
    "speed_set_impl",
    "global_set_impl",
    "color_set_impl",
    "show_set_impl",
    "rotation_set_impl",
    "scale_set_impl",
    "glow_set_impl",
    "velocity_set_impl",
    "lock_set_impl",
    "reset_impl",
    "press_action_impl",
    "load_level_impl",
    "reset_level_impl",
  ]:
    interp.implement_routine pkg, "base_bridge", sink,
      proc(args: VmArgs) = discard
  for sink in [
    "position_set_impl", "start_position_set_impl", "reset_anchor_impl",
    "claim_name_impl",
  ]:
    interp.implement_routine pkg, "base_bridge_private", sink,
      proc(args: VmArgs) = discard

  # Getters — return harmless defaults so VM code that reads them
  # doesn't trip raiseAssert.
  interp.implement_routine pkg, "base_bridge", "color_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(0))
  interp.implement_routine pkg, "base_bridge", "speed_impl",
    proc(args: VmArgs) = args.set_result(BiggestFloat(1.0))
  interp.implement_routine pkg, "base_bridge", "scale_impl",
    proc(args: VmArgs) = args.set_result(BiggestFloat(1.0))
  interp.implement_routine pkg, "base_bridge", "glow_impl",
    proc(args: VmArgs) = args.set_result(BiggestFloat(0.0))
  interp.implement_routine pkg, "base_bridge", "global_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(0))
  interp.implement_routine pkg, "base_bridge", "show_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(1))
  interp.implement_routine pkg, "base_bridge", "lock_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(0))
  interp.implement_routine pkg, "base_bridge", "rotation_impl",
    proc(args: VmArgs) = args.set_result(BiggestFloat(0.0))
  interp.implement_routine pkg, "base_bridge", "frame_created_impl",
    proc(args: VmArgs) = args.set_result(BiggestInt(0))
  interp.implement_routine pkg, "base_bridge", "start_position_impl",
    proc(args: VmArgs) =
      var v = nkTupleConstr.new_tree
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      args.set_result(v)
  interp.implement_routine pkg, "base_bridge", "position_impl",
    proc(args: VmArgs) =
      var v = nkTupleConstr.new_tree
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      args.set_result(v)
  interp.implement_routine pkg, "base_bridge", "velocity_impl",
    proc(args: VmArgs) =
      var v = nkTupleConstr.new_tree
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      v.add new_float_node(nkFloatLit, 0.0)
      args.set_result(v)

  interp.implement_routine pkg, "base_bridge", "new_instance_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        inc runner.new_instance_calls
        log_event "new_instance #" & $runner.new_instance_calls &
          " d=" & $runner.depth & " active=" & current_unit_id()

  # Mirrors host_bridge.exec_instance: switch active_unit to the clone,
  # call run_script(clone, is_instance=true) which re-enters the VM.
  interp.implement_routine pkg, "base_bridge", "exec_instance_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        inc runner.exec_instance_calls
        let clone_pnode = args.get_node(0)

        # Route to the clone's own module's run_script. In production,
        # ScriptCtx.module_name = clone_of.id picks the right one. Here
        # we infer it from the clone PNode's type: e.g. TreeType is
        # defined in build_tree_proto's wrapper, so type.sym.owner.name
        # gives us the module.
        var clone_module = ""
        if clone_pnode != nil and clone_pnode.typ != nil and
            clone_pnode.typ.sym != nil and
            clone_pnode.typ.sym.owner != nil:
          clone_module = clone_pnode.typ.sym.owner.name.s

        let run_script_sym =
          if clone_module.len > 0:
            runner.interp.select_routine(
              "run_script", module_name = clone_module
            )
          else:
            nil
        if run_script_sym == nil:
          log_event "exec_instance: no run_script for module='" &
            clone_module & "'"
          return

        let clone_ctx = ScriptCtx(
          interpreter: runner.interp,
          module_name: clone_module,
          file_name: clone_module,
          fuel: int64.high,
        )
        let clone_id = clone_module &
          "_" & current_unit_id() &
          "_clone_" & $runner.exec_instance_calls
        let mc = ManagedCtx(
          kind: CLONE,
          ctx: clone_ctx,
          label: clone_id,
          unit_id: clone_id,
        )
        runner.active_stack.add mc

        enter_vm "exec_instance " & clone_id:
          try:
            let true_node = new_int_node(nkIntLit, 1)
            discard runner.interp.call_routine(
              run_script_sym, [clone_pnode, true_node]
            )
            mc.finished = true
          except VMPause:
            runner.paused.add mc
          finally:
            discard runner.active_stack.pop()

# ----------------------------------------------------------------------
# Wrapper generation + script loading
# ----------------------------------------------------------------------

proc compute_imports(unit_id: string, all: seq[string]): string =
  ## Mirrors scripting.nim:186-200. Inject `import other1, other2, ...`
  ## for every other unit in the world, as the worker does.
  var others: HashSet[string]
  for u in all:
    if u != unit_id:
      others.incl(u)
  if others.card == 0:
    return ""
  result = "import " & others.toSeq.join(", ")

proc write_wrapper(unit_id: string, all_units: seq[string]): string =
  let imports = compute_imports(unit_id, all_units)
  # `../scripts/foo.nim` resolves relative to the wrapper's own file
  # (wrappers live in `generated/`).
  let user_rel = "../" & ScriptsSubdir & "/" & unit_id & ".nim"
  let code = build_code_template(user_rel, imports)
  let wrapper_path = TestWorldDir / GeneratedSubdir / unit_id & ".nim"
  write_file(wrapper_path, code)
  wrapper_path

proc load_unit(unit_id: string, all_units: seq[string]): bool =
  ## Generate the wrapper, then load it through the real script_ctx /
  ## interpreter pipeline — same as scripting.load_script but minus the
  ## Worker plumbing.
  let wrapper_path = write_wrapper(unit_id, all_units)
  let code = read_file(wrapper_path)

  let ctx = ScriptCtx(
    interpreter: runner.interp,
    module_name: unit_id,
    file_name: wrapper_path,
    fuel: int64.high,
  )
  let mc = ManagedCtx(
    kind: SCRIPT,
    ctx: ctx,
    label: unit_id,
    unit_id: unit_id,
  )
  runner.active_stack.add mc

  result = false
  try:
    ctx.load(wrapper_path, code)
    enter_vm "ctx.run " & unit_id:
      let paused = ctx.run()
      if paused:
        runner.paused.add mc
      else:
        mc.finished = true
    result = true
  except VMQuit as e:
    var details = e.msg
    if e.parent != nil:
      details &= " | parent: " & e.parent.msg
    log_event "VMQuit in ctx.run d=" & $runner.depth & " " & details
    echo "  FAIL ", unit_id, " VMQuit: ", details
  except CatchableError as e:
    log_event "Catchable in ctx.run d=" & $runner.depth & " " & e.msg
    echo "  FAIL ", unit_id, ": ", e.msg
  except Defect as d:
    log_event "Defect in ctx.run d=" & $runner.depth & " " & d.msg
    echo "  DEFECT ", unit_id, ": ", d.msg
  finally:
    discard runner.active_stack.pop()

proc drain_paused(): bool =
  result = true
  var iterations = 0
  const max_drain_iters = 100
  while runner.paused.len > 0 and iterations < max_drain_iters:
    inc iterations
    let batch = runner.paused
    runner.paused = @[]
    for mc in batch:
      runner.active_stack.add mc
      try:
        inc runner.resume_calls
        enter_vm "ctx.resume " & mc.label:
          let still_paused = mc.ctx.resume()
          if still_paused:
            runner.paused.add mc
          else:
            mc.finished = true
      except VMQuit as e:
        log_event "VMQuit in resume d=" & $runner.depth & " " & e.msg
        echo "  FAIL ", mc.label, " VMQuit during resume: ", e.msg
        result = false
      except CatchableError as e:
        log_event "Catchable in resume d=" & $runner.depth & " " & e.msg
        echo "  FAIL ", mc.label, " during resume: ", e.msg
        result = false
      except Defect as d:
        log_event "Defect in resume d=" & $runner.depth & " " & d.msg
        echo "  DEFECT ", mc.label, " during resume: ", d.msg
        result = false
      finally:
        discard runner.active_stack.pop()
  if runner.paused.len > 0:
    echo "  WARN: ", runner.paused.len, " contexts still paused after ",
      max_drain_iters, " drain iterations"

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

proc main(): int =
  let project_root = get_current_dir()
  let scripts_dir = project_root / TestWorldDir / ScriptsSubdir
  let generated_dir = project_root / TestWorldDir / GeneratedSubdir
  let vmlib = project_root / "vmlib"

  create_dir(generated_dir)

  # Discover all user scripts in the test world.
  var all_units: seq[string]
  for kind, path in walk_dir(scripts_dir):
    if kind == pcFile and path.ends_with(".nim"):
      all_units.add path.split_file.name
  all_units.sort

  if all_units.len == 0:
    echo "No scripts found in ", scripts_dir
    return 1

  # The interpreter resolves cross-module imports from generated/, where
  # all the wrappers live.
  runner.interp = Interpreter.init(generated_dir, vmlib)
  setup_mocks(runner.interp, vmlib)

  # Anything with a `name foo()` line counts as a proto and gets clones.
  for u in all_units:
    let src = read_file(scripts_dir / u & ".nim")
    if src.contains("\nname ") or src.startsWith("name "):
      runner.proto_modules.incl(u)

  echo "\n=== Heavy Instance Repro (real loader) ===\n"
  echo "Units: ", all_units.len, "  Protos: ", runner.proto_modules.len, "\n"

  # Pre-generate every wrapper so cross-imports resolve when each unit
  # actually loads. (Production writes wrappers on each load too, but
  # because units load via reactive watches the order is interleaved
  # enough that imports always resolve. We just batch it up front.)
  for unit_id in all_units:
    discard write_wrapper(unit_id, all_units)

  # Load every unit in order. (We skip the worker's between-load
  # reset_dependents pass — combined with our pre-generated wrappers it
  # caused cycle-resolution failures where a re-imported spawner couldn't
  # see `tree` because build_tree_proto was mid-reload. Production avoids
  # this because wrappers are written incrementally and resets are scoped
  # by actual dependency tracking, not a blanket reset.)
  var ok = true
  for unit_id in all_units:
    if not load_unit(unit_id, all_units):
      ok = false
      break
    if not drain_paused():
      ok = false
      break

  echo ""
  echo "new_instance calls: ", runner.new_instance_calls
  echo "exec_instance calls: ", runner.exec_instance_calls
  echo "sleep calls:        ", runner.sleep_calls
  echo "resume calls:       ", runner.resume_calls
  echo "instr count:        ", runner.instr_count
  echo "max depth:          ", runner.max_depth

  # Dump the tail of the event log so we can see what was happening
  # right before the failure.
  if not ok:
    echo "\n=== event log tail ==="
    let start = max(0, runner.event_log.len - 40)
    for i in start ..< runner.event_log.len:
      echo "  ", runner.event_log[i]

  if ok: 0 else: 1

when is_main_module:
  quit main()
