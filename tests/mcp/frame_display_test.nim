## The screen shows the model's frame. Enu's main thread compares each loaded
## chunk's terrain with the model's content for the frame on screen, reports
## any chunk that differs to the console, and publishes the frame once every
## chunk shows it (`display_checked_frame`). Each run here starts the build's
## script, which reloads its terrain on frame 0, then moves to another frame.

import std/[json, os, strutils, times]

type
  ToolCall* = proc(name: string, args: JsonNode): string
  CheckedFrame* = proc(id: string): int
    ## The build's `display_checked_frame`, as this test's client sees it now.

const build_id = "build_frames_display"

proc wait_for(call: ToolCall, id: string): string =
  # new things are picked up by the file watcher, so they may not exist yet
  let deadline = epoch_time() + 30
  while true:
    result = call("wait_for_script", %*{"thing_id": id})
    if not result.starts_with("Error: thing not found") or
        epoch_time() > deadline:
      return
    sleep 500

proc run_script(call: ToolCall, level, code: string) =
  # a trailing timestamp makes every write a change, so the script reruns
  write_file level / "scripts" / build_id & ".nim",
    code & "\n# " & $epoch_time() & "\n"
  let text = call.wait_for(build_id)
  if text.starts_with("Error"):
    echo "FAIL: " & code & ": " & text
    quit 1

proc fail_with_mismatches(call: ToolCall, why: string) =
  echo "FAIL: " & why
  for line in call("get_console", %*{}).split_lines:
    if "DISPLAY MISMATCH" in line:
      echo "  " & line
  quit 1

proc expect_shown(call: ToolCall, checked: CheckedFrame, frame: int) =
  ## Wait for the main thread to have seen every chunk show `frame`. A chunk
  ## that shows something else keeps it from ever doing so.
  let deadline = epoch_time() + 30
  var seen = checked(build_id)
  while seen != frame:
    if epoch_time() > deadline:
      call.fail_with_mismatches "frame " & $frame &
        " never showed in every chunk (checked: " & $seen & ")"
    seen = checked(build_id)

proc run_frame_display_tests*(call: ToolCall, checked: CheckedFrame) =
  echo ""
  echo "Frame display tests:"
  stdout.write "  each run's frame is what the terrain shows... "
  stdout.flush_file()
  let level = call("get_level_dir", %*{})
  create_dir level / "data" / build_id
  write_file level / "data" / build_id / build_id & ".json",
    $(%*{
      "id": build_id,
      "start_transform": {
        "basis": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
        "origin": [0.0, 80.0, 0.0],
      },
      "start_color": "RED",
      "edits": {},
    })
  # keep a viewer near the build so its chunks load
  discard call("set_position", %*{"x": 3.0, "y": 80.0, "z": 10.0})
  # frame n holds n + 1 blocks: each new frame takes the last one's
  call.run_script(level, """
me.frames.clear()
for f in 1 .. 3:
  me.frame = f
  me.place_block(vec3(0, f, 0), red)
""")
  for frame in [3, 0, 1, 2, 3, 0, 2, 1, 3]:
    discard call("clear_console", %*{})
    call.run_script(level, "frame = " & $frame)
    call.expect_shown(checked, frame)
    if "DISPLAY MISMATCH" in call("get_console", %*{}):
      call.fail_with_mismatches "after frame = " & $frame &
        ", the terrain wasn't the model:"
  echo "PASS"

  stdout.write "  a frame moved to during a run is what the terrain shows... "
  stdout.flush_file()
  discard call("clear_console", %*{})
  call.run_script(level, "me.frames.clear()")
  # new content in every frame, so no frame's mesh is cached yet
  call.run_script(level, """
for f in 0 .. 3:
  frame = f
  for y in 0 ..< ((f + 1) mod 4) + 1:
    me.draw_voxel(vec3(1, y, 0), blue)
frame = 0
sleep 2
frame = 1
sleep 2
frame = 2
sleep 2
frame = 3
""")
  call.expect_shown(checked, 3)
  if "DISPLAY MISMATCH" in call("get_console", %*{}):
    call.fail_with_mismatches "the terrain wasn't the model:"
  echo "PASS"

  stdout.write "  playback shows each frame, the first time through too... "
  stdout.flush_file()
  call.run_script(level, "me.frames.clear()")
  discard call("clear_console", %*{})
  # new content in every frame again, so the first loop bakes every mesh
  call.run_script(level, """
for f in 0 .. 3:
  frame = f
  for y in 0 .. f:
    me.draw_voxel(vec3(2, y, 0), green)
me.play(fps = 0.5)
""")
  # each frame is up for two seconds; every one must show in full, in order,
  # through the first loop and back to the start
  for frame in [0, 1, 2, 3, 0]:
    call.expect_shown(checked, frame)
  let played = call("get_console", %*{})
  call.run_script(level, "frame = 0") # stops playback
  if "DISPLAY MISMATCH" in played:
    call.fail_with_mismatches "a frame showed another frame's mesh:"
  echo "PASS"
