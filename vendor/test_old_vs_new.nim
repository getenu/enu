import gdext

# Test to show the difference between old unfixed approach and new GDScript-compatible approach

# Expected values from GDScript
let expectedRight = vector3(0.707107, 0.0, -0.707107)
let expectedUp = vector3(0.0, 1.0, 0.0)
let expectedBack = vector3(0.707107, 0.0, 0.707107)

echo "=== Testing GDScript-Compatible Approach ==="

# Our new GDScript-compatible constructor
let basis_new = basis(expectedRight, expectedUp, expectedBack)

echo "New approach (stores columns as rows):"
echo "basis[0] = ", basis_new[0], " (expected: ", expectedRight, ")"
echo "basis[1] = ", basis_new[1], " (expected: ", expectedUp, ")"  
echo "basis[2] = ", basis_new[2], " (expected: ", expectedBack, ")"
echo ""

# Simulate old broken approach (direct field assignment like unfixed gdext-nim would do)
var basis_old = Basis()
basis_old.x = expectedRight  # This would be wrong with raw row access
basis_old.y = expectedUp
basis_old.z = expectedBack

echo "Old broken approach (stores columns directly, wrong for row access):"
echo "basis[0] = ", basis_old[0], " (should be: ", expectedRight, ")"
echo "basis[1] = ", basis_old[1], " (should be: ", expectedUp, ")"
echo "basis[2] = ", basis_old[2], " (should be: ", expectedBack, ")"
echo ""

echo "Results:"
echo "New approach matches GDScript: ", basis_new[0] == expectedRight
echo "Old approach matches GDScript: ", basis_old[0] == expectedRight