## VM Test Runner
## Runs test scripts inside the Nim VM to test vmlib/enu API

{.push warning[GcUnsafe2]:off.}

import std/[os, strutils, sequtils, algorithm]
import core
import libs/[interpreters, eval]
import pkg/compiler/vm

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

  # Mock write_stack_trace
  interp.implement_routine pkg, "base_bridge", "write_stack_trace_impl",
    proc(args: VmArgs) =
      echo "  [VM] Stack trace requested"

  # Mock exit
  interp.implement_routine pkg, "base_bridge_private", "exit_impl",
    proc(args: VmArgs) =
      let code = args.get_int(0)
      echo "  [VM] Exit called with code: ", code

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
