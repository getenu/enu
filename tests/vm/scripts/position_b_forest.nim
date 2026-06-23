## Calls Tree.new with position parameter. When Tree.new is already compiled
## (from position_a_tree.nim), vmgen hits the genProc else-branch on the call,
## potentially corrupting the caller's register allocation.

import std/[tables]
import types, base_api, base_bridge, position_a_tree

var test_unit = Unit()
test_unit.query_results = initTable[string, seq[Unit]]()
register_active(test_unit)

# Add local variables to increase register pressure before Tree.new calls.
# This is needed to trigger the genProc else-branch truncation bug:
# when the calling proc's regInfo.len > Tree.new's s.offset, the else-branch
# truncates regInfo, corrupting register allocation for subsequent code.
var v1 = 1; var v2 = 2; var v3 = 3; var v4 = 4; var v5 = 5
var v6 = 6; var v7 = 7; var v8 = 8; var v9 = 9; var v10 = 10
var v11 = 11; var v12 = 12; var v13 = 13; var v14 = 14; var v15 = 15
var v16 = 16; var v17 = 17; var v18 = 18; var v19 = 19; var v20 = 20
var v21 = 21; var v22 = 22; var v23 = 23; var v24 = 24; var v25 = 25
var v26 = 26; var v27 = 27; var v28 = 28; var v29 = 29; var v30 = 30
var v31 = 31; var v32 = 32; var v33 = 33; var v34 = 34; var v35 = 35

Tree.new(height = 5, position = vec3(35.0, 0.0, -20.0))
Tree.new(height = 8, canopy_color = blue, position = vec3(40.0, 0.0, -25.0))
Tree.new(height = 4, trunk_color = red, position = vec3(32.0, 0.0, -28.0))

echo "position_b_forest: passed (v1=", v1, " v35=", v35, ")"
