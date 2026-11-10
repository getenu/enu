import unittest2
import std/[json, jsonutils, os]
import core
import models/colors
import models/builds
import models/bots
import models/states
import models/voxels/[store, codec]
import models/serializers {.all.}

suite "Color Serialization":
  test "color to json and back - blue":
    let blue = ACTION_COLORS[Blue]
    let json_node = json_utils.to_json(blue)
    check json_node.get_str == "BLUE"

  test "color to json and back - red":
    let red = ACTION_COLORS[RED]
    let json_node = json_utils.to_json(red)
    check json_node.get_str == "RED"

  test "eraser color serializes to empty string":
    let eraser = ACTION_COLORS[Eraser]
    let json_node = json_utils.to_json(eraser)
    check json_node.get_str == ""

  test "color from json - named color":
    var restored: Color
    restored.from_json(%"green")
    check restored == ACTION_COLORS[Green]

  test "color from json - empty string is eraser":
    var restored: Color
    restored.from_json(%"")
    check restored == ACTION_COLORS[Eraser]

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
    let json_str =
      """
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
    let json_str =
      """
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

suite "Build Serialization":
  test "build serializes to json string":
    let build = Build.init(
      id = "build_test123",
      transform = Transform.init(origin = vec3(10.0, 20.0, 30.0)),
      color = ACTION_COLORS[BLUE],
    )
    let json_str = $build
    let json_node = parse_json(json_str)
    check json_node["id"].get_str == "build_test123"
    check json_node["start_color"].get_str == "BLUE"
    check json_node["start_transform"]["origin"][0].get_float == 10.0
    check json_node["start_transform"]["origin"][1].get_float == 20.0
    check json_node["start_transform"]["origin"][2].get_float == 30.0

  test "build round-trip serialization":
    let original = Build.init(
      id = "build_roundtrip",
      transform = Transform.init(origin = vec3(5.0, 10.0, 15.0)),
      color = ACTION_COLORS[Red],
    )
    let json_str = $original
    let json_node = parse_json(json_str)
    var restored: Build
    restored.from_json(json_node)
    check restored.id == original.id
    check restored.start_color == original.start_color
    check restored.start_transform.origin.x == original.start_transform.origin.x
    check restored.start_transform.origin.y == original.start_transform.origin.y
    check restored.start_transform.origin.z == original.start_transform.origin.z

suite "Bot Serialization":
  test "bot serializes to json string":
    let bot = Bot.init(
      id = "bot_test456",
      transform = Transform.init(origin = vec3(1.0, 2.0, 3.0)),
    )
    let json_str = $bot
    let json_node = parse_json(json_str)
    check json_node["id"].get_str == "bot_test456"
    check json_node["start_transform"]["origin"][0].get_float == 1.0
    check json_node["start_transform"]["origin"][1].get_float == 2.0
    check json_node["start_transform"]["origin"][2].get_float == 3.0

  test "bot round-trip serialization":
    let original = Bot.init(
      id = "bot_roundtrip",
      transform = Transform.init(origin = vec3(100.0, 200.0, 300.0)),
    )
    let json_str = $original
    let json_node = parse_json(json_str)
    var restored: Bot
    restored.from_json(json_node)
    check restored.id == original.id
    check restored.start_transform.origin.x == original.start_transform.origin.x
    check restored.start_transform.origin.y == original.start_transform.origin.y
    check restored.start_transform.origin.z == original.start_transform.origin.z

suite "Frame Serialization":
  test "frames round-trip with only their manual blocks":
    let dir = get_temp_dir() / "enu_frames_test"
    remove_dir dir
    state = GameState.init
    var config = state.config
    config.data_dir = dir
    state.config = config
    let build = Build.init(id = "build_frames_save")
    for (index, color) in [(0, RED), (1, BLUE), (2, GREEN), (3, RED), (4, BLUE)]:
      build.go_to_frame(index)
      build.draw(vec3(index.float, 0, 0), (PERSISTED, ACTION_COLORS[color]))
      build.draw(vec3(index.float, 1, 0), (TRANSIENT, ACTION_COLORS[color]))
    build.go_to_frame(2)
    build.save_frames(true)
    check file_exists(dir / build.id / "frames" / "002.bin")
    check build.id notin parse_json($build)["edits"]

    let restored = Build.init(id = "build_frames_save")
    restored.load_frames_sidecar(
      %*{"frames": {"count": build.frames_len, "frame": build.frame}}
    )
    restored.restore_edits
    check restored.frames_len == 5
    check restored.frame == 2
    check restored.voxels.get_edit(vec3(2, 0, 0)) ==
      (PERSISTED, ACTION_COLORS[GREEN])
    check vec3(2, 1, 0) notin restored
    check vec3(2, 0, 0) in restored
    for index in [0, 1, 3, 4]:
      let saved = build.voxels.frame_edits(build.frame_order.ids[index])
      check restored.voxels.frame_edits(restored.frame_order.ids[index]).chunks ==
        saved.chunks
      check saved.chunks.len == 1
    remove_dir dir

  test "a big single-frame build saves its blocks as one frame file":
    let dir = get_temp_dir() / "enu_frames_big_test"
    remove_dir dir
    var config = state.config
    config.data_dir = dir
    state.config = config
    let build = Build.init(id = "build_frames_big")
    for x in 0 .. EDITS_JSON_LIMIT:
      build.draw(vec3(x.float, 0, 0), (PERSISTED, ACTION_COLORS[RED]))
    build.save
    check file_exists(dir / build.id / "frames" / "000.bin")
    let json = parse_json(read_file(build.data_file))
    check json["frames"]["count"].get_int == 1
    check build.id notin json["edits"]

    let restored = Build.init(id = "build_frames_big")
    restored.load_frames_sidecar(json)
    restored.restore_edits
    check restored.frames_len == 1
    check restored.voxels.get_edit(vec3(EDITS_JSON_LIMIT.float, 0, 0)) ==
      (PERSISTED, ACTION_COLORS[RED])
    remove_dir dir
