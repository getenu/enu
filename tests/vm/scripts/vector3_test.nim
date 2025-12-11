# Test Vector3 operations
import types

# Test vector creation
let v1 = vec3(1.0, 2.0, 3.0)
assert v1.x == 1.0
assert v1.y == 2.0
assert v1.z == 3.0

# Test vector addition
let v2 = vec3(4.0, 5.0, 6.0)
let v3 = v1 + v2
assert v3.x == 5.0
assert v3.y == 7.0
assert v3.z == 9.0

# Test vector subtraction
let v4 = v2 - v1
assert v4.x == 3.0
assert v4.y == 3.0
assert v4.z == 3.0

# Test scalar multiplication
let v5 = v1 * 2.0
assert v5.x == 2.0
assert v5.y == 4.0
assert v5.z == 6.0

# Test equality
assert v1 == vec3(1.0, 2.0, 3.0)
assert v1 != v2

# Test direction constants
assert UP == vec3(0, 1, 0)
assert DOWN == vec3(0, -1, 0)
assert FORWARD == vec3(0, 0, -1)
assert BACK == vec3(0, 0, 1)
assert LEFT == vec3(-1, 0, 0)
assert RIGHT == vec3(1, 0, 0)

echo "Vector3 tests passed!"
