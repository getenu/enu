import std/strformat

# Simple test to understand what's happening with basis indexing
type
  Vector3 = array[3, float32]
  Basis = object
    x: Vector3
    y: Vector3  
    z: Vector3

proc vector3(x, y, z: float32): Vector3 = [x, y, z]

proc basis(xAxis, yAxis, zAxis: Vector3): Basis = 
  Basis(x: xAxis, y: yAxis, z: zAxis)

proc `[]`(self: Basis; index: int): Vector3 =
  if index notin 0..2: raise newException(IndexDefect, &"index must be in [0..2]; but got {index}")
  cast[ptr array[3, Vector3]](addr self)[][index]

# Test with the expected values
let expectedRight = vector3(0.707107, 0.0, -0.707107)
let expectedUp = vector3(0.0, 1.0, 0.0)
let expectedBack = vector3(0.707107, 0.0, 0.707107)

echo "=== Testing Current Approach ==="
let basis_test = basis(expectedRight, expectedUp, expectedBack)

echo "Input vectors:"
echo "  expectedRight = ", expectedRight
echo "  expectedUp = ", expectedUp  
echo "  expectedBack = ", expectedBack
echo ""

echo "Stored in basis:"
echo "  basis.x = ", basis_test.x
echo "  basis.y = ", basis_test.y
echo "  basis.z = ", basis_test.z
echo ""

echo "Retrieved via indexing:"
echo "  basis[0] = ", basis_test[0]
echo "  basis[1] = ", basis_test[1]
echo "  basis[2] = ", basis_test[2]
echo ""

echo "Match check:"
echo "  basis[0] == expectedRight: ", basis_test[0] == expectedRight
echo "  basis[1] == expectedUp: ", basis_test[1] == expectedUp
echo "  basis[2] == expectedBack: ", basis_test[2] == expectedBack