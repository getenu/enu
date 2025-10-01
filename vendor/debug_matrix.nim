import gdext

# Debug what our fixed indexing returns vs what it should return

var basis = Basis()

# Set the values as GDScript from_euler stores them
basis.x = vector3(0.707107, 0.0, -0.707107)   # Row 0
basis.y = vector3(0.0, 1.0, 0.0)              # Row 1  
basis.z = vector3(0.707107, 0.0, 0.707107)    # Row 2

echo "=== Debug Matrix Indexing ==="
echo "Internal row storage:"
echo "basis.x (row 0) = ", basis.x
echo "basis.y (row 1) = ", basis.y  
echo "basis.z (row 2) = ", basis.z
echo ""

echo "Our fixed indexing (extracts columns):"
echo "basis[0] (col 0) = ", basis[0]  # Should be (basis.x.x, basis.y.x, basis.z.x)
echo "basis[1] (col 1) = ", basis[1]  # Should be (basis.x.y, basis.y.y, basis.z.y)
echo "basis[2] (col 2) = ", basis[2]  # Should be (basis.x.z, basis.y.z, basis.z.z)
echo ""

echo "Manual column extraction:"
echo "col 0 = (", basis.x.x, ", ", basis.y.x, ", ", basis.z.x, ")"
echo "col 1 = (", basis.x.y, ", ", basis.y.y, ", ", basis.z.y, ")"  
echo "col 2 = (", basis.x.z, ", ", basis.y.z, ", ", basis.z.z, ")"
echo ""

echo "What GDScript returns (row access that looks like columns):"
echo "Should match GDScript basis[0] = (0.707107, 0.0, -0.707107)"
echo "Should match GDScript basis[1] = (0.0, 1.0, 0.0)"
echo "Should match GDScript basis[2] = (0.707107, 0.0, 0.707107)"