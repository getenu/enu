# Test custom testing framework in VM
import testing
import types

suite "Vector3 with testing framework":
  test "vector creation":
    let v = vec3(1.0, 2.0, 3.0)
    check v.x == 1.0
    check v.y == 2.0
    check v.z == 3.0

  test "vector addition":
    let v1 = vec3(1.0, 2.0, 3.0)
    let v2 = vec3(4.0, 5.0, 6.0)
    let v3 = v1 + v2
    check v3.x == 5.0
    check v3.y == 7.0
    check v3.z == 9.0

test_summary()
