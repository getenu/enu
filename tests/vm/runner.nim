## VM Test Runner
## Runs test scripts inside the Nim VM to test vmlib/enu API

{.push warning[GcUnsafe2]:off.}

import std/[os, strutils, sequtils, algorithm]
import core
import libs/[interpreters, eval]
import pkg/compiler/[vm, ast]

type
  TestResult = object
    name: string
    passed: bool
    error: string

  VMTestRunner = object
    interp: Interpreter
    results: seq[TestResult]
    output: seq[string]
    frame: int

var runner: VMTestRunner

proc setup_mock_functions(interp: Interpreter) =
  const pkg = "enu"

  # Mock echo_console to capture output
  interp.implement_routine pkg, "base_bridge", "echo_console_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        let msg = args.get_string(0)
        runner.output.add(msg)
        echo "  [VM] ", msg

  # Mock frame_count
  interp.implement_routine pkg, "base_bridge", "frame_count_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        inc runner.frame
        args.set_result(runner.frame)

  # Mock yield_script to allow execution to continue
  interp.implement_routine pkg, "base_bridge_private", "yield_script_impl",
    proc(args: VmArgs) =
      discard

  # Mock action_running getter
  interp.implement_routine pkg, "base_bridge_private", "action_running_impl",
    proc(args: VmArgs) =
      args.set_result(BiggestInt(0))  # false - not running

  # Mock action_running setter
  interp.implement_routine pkg, "base_bridge_private", "action_running_set_impl",
    proc(args: VmArgs) =
      discard  # ignore setting action_running in tests

  # Mock sleep_impl - the bridged_to_host macro creates sleep_impl_impl
  interp.implement_routine pkg, "base_bridge_private", "sleep_impl_impl",
    proc(args: VmArgs) =
      discard  # sleep is a no-op in tests

  # Mock write_stack_trace
  interp.implement_routine pkg, "base_bridge", "write_stack_trace_impl",
    proc(args: VmArgs) =
      echo "  [VM] Stack trace requested"

  # Mock exit
  interp.implement_routine pkg, "base_bridge_private", "exit_impl",
    proc(args: VmArgs) =
      let code = args.get_int(0)
      echo "  [VM] Exit called with code: ", code

  # Mock register_template_node - called when types like Player, Bot, etc are registered
  interp.implement_routine pkg, "base_bridge", "register_template_node_impl",
    proc(args: VmArgs) =
      discard

  # Mock signal_test_complete - called by testing framework
  interp.implement_routine pkg, "base_bridge", "signal_test_complete_impl",
    proc(args: VmArgs) =
      let exit_code = args.get_int(0)
      echo "  [VM] Test complete with exit code: ", exit_code

  # Mock has_block_at - returns false (no blocks in test environment)
  interp.implement_routine pkg, "builds", "has_block_at_impl",
    proc(args: VmArgs) =
      args.set_result(false)

  # Mock block_color_at - returns 0 (Eraser) since no blocks exist
  interp.implement_routine pkg, "builds", "block_color_at_impl",
    proc(args: VmArgs) =
      args.set_result(BiggestInt(0))

  # Note: register_active_impl is NOT mocked - let the stub set current_active_unit

  # Mock get_last_error for error checking - returns ErrorData tuple (id: int, msg: string)
  interp.implement_routine pkg, "vm_bridge_utils", "get_last_error_impl",
    proc(args: VmArgs) =
      # Return (0, "") - no error
      var result_node = nkTupleConstr.new_tree
      result_node.add new_int_node(nkIntLit, 0)
      result_node.add new_str_node(nkStrLit, "")
      args.set_result(result_node)

  # Mock now_seconds - returns seconds since test start
  var test_start_time = 0.0
  interp.implement_routine pkg, "base_bridge", "now_seconds_impl",
    proc(args: VmArgs) =
      {.cast(gcsafe).}:
        # Increment by small amount each call to simulate time passing
        test_start_time += 0.001
        args.set_result(test_start_time)

proc run_test_script(script_path: string): TestResult =
  result.name = script_path.extract_filename.change_file_ext("")

  let code = read_file(script_path)
  var ctx = ScriptCtx(interpreter: runner.interp)
  runner.output.set_len(0)

  try:
    ctx.load(script_path.extract_filename, code)
    discard ctx.run()
    result.passed = true
  except CatchableError as e:
    result.passed = false
    result.error = e.msg

proc run_all_tests(test_dir, vmlib_path: string): int =
  let script_dir = test_dir / "scripts"
  runner.interp = Interpreter.init(script_dir, vmlib_path)
  setup_mock_functions(runner.interp)

  var test_files: seq[string]
  for kind, path in walk_dir(script_dir):
    if kind == pcFile and path.ends_with(".nim"):
      test_files.add(path)

  test_files.sort()

  echo "\n=== Running VM Tests ===\n"

  for test_file in test_files:
    echo "Running: ", test_file.extract_filename
    let test_result = run_test_script(test_file)
    runner.results.add(test_result)

    if test_result.passed:
      echo "  PASSED"
    else:
      echo "  FAILED: ", test_result.error
    echo ""

  # Summary
  let passed = runner.results.filter_it(it.passed).len
  let total = runner.results.len

  echo "=== Results ==="
  echo passed, "/", total, " tests passed"

  if passed < total:
    result = 1
  else:
    result = 0

when is_main_module:
  let project_root = get_current_dir()
  let test_dir = project_root / "tests/vm"
  let vmlib_path = project_root / "vmlib"
  quit run_all_tests(test_dir, vmlib_path)
