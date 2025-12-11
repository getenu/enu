import unittest2
import std/[json, jsonutils]
import core
import models/colors
import models/serializers {.all.}

suite "Color Serialization":
  test "color to json and back - blue":
    let blue = action_colors[Blue]
    let json_node = json_utils.to_json(blue)
    check json_node.get_str == "Blue"

  test "color to json and back - red":
    let red = action_colors[Red]
    let json_node = json_utils.to_json(red)
    check json_node.get_str == "Red"

  test "eraser color serializes to empty string":
    let eraser = action_colors[Eraser]
    let json_node = json_utils.to_json(eraser)
    check json_node.get_str == ""

  test "color from json - named color":
    var restored: Color
    restored.from_json(%"green")
    check restored == action_colors[Green]

  test "color from json - empty string is eraser":
    var restored: Color
    restored.from_json(%"")
    check restored == action_colors[Eraser]

  test "hex color round-trip":
    let custom = col"ff5500"
    let json_node = json_utils.to_json(custom)
    var restored: Color
    restored.from_json(json_node)
    check restored.r == custom.r
    check restored.g == custom.g
    check restored.b == custom.b

suite "Vector3 Serialization":
  test "vector3 from json array":
    let json_node = %[1.0, 2.0, 3.0]
    var v: Vector3
    v.from_json(json_node)
    check v.x == 1.0
    check v.y == 2.0
    check v.z == 3.0

  test "vector3 from json with negative values":
    let json_node = %[-5.5, 0.0, 100.25]
    var v: Vector3
    v.from_json(json_node)
    check v.x == -5.5
    check v.y == 0.0
    check v.z == 100.25

suite "Transform Serialization":
  test "transform from json":
    let json_str = """
    {
      "basis": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
      "origin": [10.0, 20.0, 30.0]
    }
    """
    let json_node = parse_json(json_str)
    var t: Transform
    t.from_json(json_node)
    check t.origin.x == 10.0
    check t.origin.y == 20.0
    check t.origin.z == 30.0

  test "transform from json with old basis format":
    let json_str = """
    {
      "basis": {"elements": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]},
      "origin": [5.0, 10.0, 15.0]
    }
    """
    let json_node = parse_json(json_str)
    var t: Transform
    t.from_json(json_node)
    check t.origin.x == 5.0
    check t.origin.y == 10.0
    check t.origin.z == 15.0
