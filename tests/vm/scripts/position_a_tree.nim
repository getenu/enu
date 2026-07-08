## Defines TreeType class with position param in constructor.
## This module is imported by position_b_forest.nim to test cross-module
## constructor calls with position parameter.

import std/[tables]
import types, core, base_bridge

var test_thing = Thing()
test_thing.query_results = initTable[string, seq[Thing]]()
register_active(test_thing)

type TreeType* = ref object of Build
  height*: int
  trunk_color*: Colors
  canopy_color*: Colors

let Tree* = TreeType()

proc new*(
    instance: TreeType,
    height = 6,
    trunk_color = brown,
    canopy_color = green,
    global = false,
    speed = 1.0,
    color = eraser,
    position = UNSET_POSITION,
): TreeType {.discardable.} =
  assert not instance.is_nil
  result = TreeType()
  result.seed = active_thing().seed
  result.height = height
  result.trunk_color = trunk_color
  result.canopy_color = canopy_color

echo "position_a_tree: class defined"
