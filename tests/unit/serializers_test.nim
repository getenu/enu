import unittest2
import std/[json, jsonutils, os, options, tables]
import core
import models/colors
import models/builds
import models/bots
import models/states
import models/voxels/[store, codec]
import models/bakes
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
  # placed blocks would otherwise join the builds of earlier tests
  dont_join = true

  test "frame files round-trip with only their manual blocks":
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
    restored.load_frames(
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
    restored.load_frames(json)
    restored.restore_edits
    check restored.frames_len == 1
    check restored.voxels.get_edit(vec3(EDITS_JSON_LIMIT.float, 0, 0)) ==
      (PERSISTED, ACTION_COLORS[RED])
    remove_dir dir

  test "holes save unmarked":
    let dir = get_temp_dir() / "enu_frames_holes_test"
    remove_dir dir
    var config = state.config
    config.data_dir = dir
    state.config = config
    let build = Build.init(id = "build_frames_holes")
    build.draw(vec3(0, 0, 0), (HOLE, ACTION_COLORS[ERASER]))
    build.draw(vec3(0, 0, 0), (TRANSIENT, ACTION_COLORS[RED]))
    check build.voxels.get_edit(vec3(0, 0, 0)) == (HOLE, ACTION_COLORS[RED])

    build.voxels.flush_edits_for_save()
    let edits = parse_json($build)["edits"][build.id]
    check edits[0][1] == %*[HOLE.ord, ""]

    build.go_to_frame(1)
    build.save_frames(true)
    let restored = Build.init(id = "build_frames_holes")
    restored.load_frames(%*{"frames": {"count": 2, "frame": 1}})
    restored.go_to_frame(0)
    restored.restore_edits
    check restored.voxels.get_edit(vec3(0, 0, 0)) == (HOLE, ACTION_COLORS[ERASER])
    remove_dir dir

  test "small animated builds keep every frame's blocks in the JSON":
    let build = Build.init(id = "build_frames_inline")
    for (index, color) in [(0, RED), (1, BLUE), (2, GREEN)]:
      build.go_to_frame(index)
      build.draw(vec3(index.float, 0, 0), (PERSISTED, ACTION_COLORS[color]))
      build.draw(vec3(index.float, 1, 0), (TRANSIENT, ACTION_COLORS[color]))
    build.go_to_frame(1)
    build.voxels.flush_edits_for_save()
    let json = parse_json(build.to_json_string(frame_files = false))
    check build.id notin json["edits"]
    check json["frames"]["count"].get_int == 3
    check json["frames"]["edits"].len == 3
    check json["frames"]["edits"][2].len == 1

    let restored = Build.init(id = "build_frames_inline")
    restored.load_frames(json)
    restored.restore_edits
    check restored.frames_len == 3
    check restored.frame == 1
    check restored.voxels.get_edit(vec3(1, 0, 0)) ==
      (PERSISTED, ACTION_COLORS[BLUE])
    check vec3(1, 1, 0) notin restored
    for index in 0 ..< 3:
      check restored.voxels.frame_edits(restored.frame_order.ids[index]).chunks ==
        build.voxels.frame_edits(build.frame_order.ids[index]).chunks

suite "Bake Serialization":
  dont_join = true

  test "bakes round-trip in the JSON, or in bakes.bin when they're big":
    let dir = get_temp_dir() / "enu_bakes_test"
    remove_dir dir
    var config = state.config
    config.data_dir = dir
    state.config = config
    for (id, count) in [
      ("build_bakes_small", 10), ("build_bakes_big", EDITS_JSON_LIMIT + 1)
    ]:
      let build = Build.init(id = id)
      var cells: seq[(Vector3, VoxelInfo)]
      for x in 0 ..< count:
        cells.add (vec3(x.float, 0, 0), (TRANSIENT, ACTION_COLORS[RED]))
      var entry = BakeEntry(
        end_pose: Transform.init(origin = vec3(2, 0, 0)),
        end_frame: 1,
        color: some(ACTION_COLORS[GREEN]),
      )
      entry.frames[0] = pack_frame(build.shared, cells)
      entry.frames[1] = pack_frame(build.shared, cells[0 ..< 1])
      build.bakes["key"] = entry
      inc build.bakes_serial
      build.save
      let big = count > EDITS_JSON_LIMIT
      check file_exists(dir / id / "bakes.bin") == big
      let json = parse_json(read_file(build.data_file))
      check ("bakes" in json) == not big

      var restored: Build
      restored.from_json(json)
      check "key" in restored.bakes
      let back = restored.bakes["key"]
      check back.frames == entry.frames
      check back.end_pose.origin == vec3(2, 0, 0)
      check back.end_frame == 1
      check back.color == some(ACTION_COLORS[GREEN])
      check back.drawing.is_none
    remove_dir dir

  test "script colors keep their palette slots through a save and load":
    # colors a script computes aren't 8-bit exact, but the palette saves as
    # #rrggbb: they're snapped when packed, so the saved indices still match
    let build = Build.init(id = "build_palette_round_trip")
    let colors = [
      Color(r: 0.12, g: 0.5678, b: 0.8, a: 1.0),
      Color(r: 0.1215, g: 0.5679, b: 0.8001, a: 1.0), # same #rrggbb
      Color(r: 0.7, g: 0.2, b: 0.31, a: 0.5),
    ]
    var indices: seq[int]
    for color in colors:
      indices.add pack_color_index(build.shared, color)
    check indices[0] == indices[1]
    let json = parse_json(build.to_json_string(frame_files = false))
    var restored: Build
    restored.from_json(json)
    check restored.shared.palette.len == build.shared.palette.len
    for i, color in colors:
      check resolve_color(restored.shared, indices[i]) ==
        resolve_color(build.shared, indices[i])
      check pack_color_index(restored.shared, color) == indices[i]

suite "Bake Cleanup":
  test "a compile drops recordings whose key is gone or out of date":
    let build = Build.init(id = "build_bake_cleanup")
    let keys = [
      bake_key("1", "#live", ""),
      bake_key("1", "#live", "7"), # an input variant: kept
      bake_key("1", "#renamed", ""),
      bake_key("0", "#live", ""), # an older Enu bake key
    ]
    for key in keys:
      build.bakes[key] = BakeEntry()
    build.script_ctx = ScriptCtx(
      bake_sites: @[(file: "", line: 1, key: "live", enu: "1")],
      bakes_known: true,
    )
    build.drop_stale_bakes()
    check build.bakes.len == 2
    check keys[0] in build.bakes
    check keys[1] in build.bakes
