# Test Timestamp and Duration types
import types
import base_api

# Test now() returns a Timestamp
let t1 = now()
let t2 = now()

# t2 should be after t1 (mock increments by 0.001 each call)
assert t2 > t1, "now() should return increasing timestamps"

# Test Duration from subtraction
let elapsed = t2 - t1
assert elapsed.seconds > 0, "elapsed time should be positive"

# Test Duration.milliseconds
assert elapsed.milliseconds > 0, "elapsed milliseconds should be positive"
assert elapsed.milliseconds == elapsed.seconds * 1000.0, "milliseconds should be seconds * 1000"

# Test Duration arithmetic
let d1 = t2 - t1
let d2 = t2 - t1
let combined = d1 + d2
assert combined.seconds == d1.seconds + d2.seconds, "durations should add"

# Test Duration comparison
assert d1 == d2, "equal durations should be equal"
let t3 = now()
let d3 = t3 - t1
assert d3 > d1, "longer duration should be greater"

# Test Duration to string
let duration_str = $elapsed
assert duration_str.len > 0, "duration string should not be empty"

# Test Timestamp arithmetic with Duration
let t_plus = t1 + elapsed
let t_minus = t2 - elapsed
# These should be approximately equal (t1 + (t2-t1) ≈ t2)
assert t_plus > t1, "timestamp + duration should be later"

echo "Timing tests passed!"
