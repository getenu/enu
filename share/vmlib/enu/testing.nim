## Simple testing framework for Enu VM tests
## Follows unittest API but works in NimScript/VM mode

import std/strutils
import base_bridge
export signal_test_complete

var
  current_suite: string
  total_tests: int
  passed_tests: int
  failed_tests: int
  test_failed: bool
  failure_msg: string

template suite*(name: string, body: untyped) =
  ## A group of related tests: `suite "gravity": ...`.
  current_suite = name
  echo "Suite: ", name
  body

template test*(name: string, body: untyped) =
  ## One test with a name. Put `check`s inside.
  inc total_tests
  test_failed = false
  failure_msg = ""
  body
  if test_failed:
    inc failed_tests
    echo "  [FAIL] ", name
    echo "    ", failure_msg
  else:
    inc passed_tests
    echo "  [OK] ", name

template check*(cond: untyped) =
  ## Check that something is true. If it isn't, the test fails and
  ## tells you what went wrong.
  if not test_failed:
    if not cond:
      test_failed = true
      failure_msg = ast_to_str(cond) & " was false"

template require*(cond: untyped) =
  ## The same as `check`.
  check(cond)

proc test_summary*() =
  ## Print how many tests passed and failed. Call it at the end.
  echo ""
  echo "=== Summary ==="
  echo total_tests, " tests run: ", passed_tests, " passed, ", failed_tests, " failed"
  signal_test_complete(failed_tests)

proc tests_failed*(): bool =
  ## `true` if any test has failed so far.
  failed_tests > 0
