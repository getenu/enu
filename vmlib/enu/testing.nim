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
  current_suite = name
  echo "Suite: ", name
  body

template test*(name: string, body: untyped) =
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
  if not test_failed:
    if not cond:
      test_failed = true
      failure_msg = ast_to_str(cond) & " was false"

template require*(cond: untyped) =
  check(cond)

proc test_summary*() =
  echo ""
  echo "=== Summary ==="
  echo total_tests, " tests run: ", passed_tests, " passed, ", failed_tests, " failed"
  signal_test_complete(failed_tests)

proc tests_failed*(): bool =
  failed_tests > 0
