# Regression test checker. After all spawners finish, count units. If the
# count exceeds the known-correct baseline, signal failure.
#
# Why: this fixture's spawners create a fixed number of clones in their
# module-init bodies. With the exit() workaround in build/bot_code_template
# (see src/libs/eval.nim near closePContext), the count is deterministic.
# Without exit(), Enu's processModule runs closePContext + interpreterCode
# after each script completes naturally, which re-emits and re-executes
# generic instance bytecode (including class constructors), causing each
# spawner's `.new(...)` calls to fire repeatedly.
#
# Tolerance is generous so timing/clone-load skew doesn't flake the test.
sleep 3.0  # let all spawners complete their .new() calls
let n = all_units().len
echo "BULK_SPAWN_CHECK: ", n, " units"
const expected = 27
const max_allowed = expected + 10  # generous tolerance
if n > max_allowed:
  echo "FAIL: too many units (", n, " > ", max_allowed, ")"
  signal_test_complete(1)
else:
  echo "OK"
  signal_test_complete(0)
