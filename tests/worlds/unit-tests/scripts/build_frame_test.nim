import testing, builds_private

speed = 0

let
  here = me.position
  spot = vec3(1, 0, 0)
  hand = vec3(2, 0, 0)

proc color_at(offset: Vector3): Color =
  block_color_at(here + offset)

proc raises(body: proc()): bool =
  try:
    body()
  except CatchableError, Defect:
    return true

suite "Frame Animation":
  test "every build has a frame":
    me.frames.clear()
    check me.frames.len == 1
    check me.frame == 0

  test "frame = n past the end adds empty frames":
    me.draw_voxel(spot, red)
    me.frame = 2
    check me.frames.len == 3
    check not has_block_at(here + spot)
    me.frame = 0
    check color_at(spot) == red

  test "changes go straight into the current frame":
    me.frame = 1
    me.draw_voxel(spot, green)
    me.place_block(hand, red)
    me.frame = 0
    check not has_block_at(here + hand)
    me.frame = 1
    check color_at(spot) == green
    check color_at(hand) == red

  test "assigning a frame copies it":
    me.frames[2] = me.frames[1]
    me.frame = 2
    check color_at(spot) == green
    check color_at(hand) == red
    me.frames[4] = me.frames[0]
    check me.frames.len == 5
    check me.frames[^1].index == 4

  test "insert and add copy frames":
    me.frames.insert(me.frames[0], 1)
    check me.frames.len == 6
    check me.frame == 3 # the current frame moves up with the rest
    me.frames.add me.frames[me.frame]
    check me.frames.len == 7
    me.frame = 6
    check color_at(spot) == green
    check color_at(hand) == red

  test "delete moves later frames down":
    me.frames.delete(1)
    check me.frames.len == 6
    me.frames.delete(3 .. 4)
    check me.frames.len == 4
    check me.frame == 3
    me.frame = 1
    check color_at(spot) == green

  test "clear empties one frame and paste lays one over another":
    me.frame = 3
    me.frames[3].clear()
    check not has_block_at(here + hand)
    check not has_block_at(here + spot)
    me.frames[3].paste(me.frames[0])
    check color_at(spot) == red
    check not has_block_at(here + hand)
    me.frames[3].paste(me.frames[1])
    check color_at(spot) == green
    check color_at(hand) == red

  test "frames past 63 raise":
    check raises(proc() = me.frame = 64)
    check raises(proc() = discard me.frames[me.frames.len])

  test "play only changes the display, and the script can draw meanwhile":
    me.frames.clear()
    me.draw_voxel(spot, red)
    me.frame = 2
    me.draw_voxel(spot, green)
    me.play(fps = 5.0)
    sleep(0.5)
    check me.frame == 2
    check color_at(spot) == green
    me.frame = 0 # the script draws into frame 0 while playback runs on
    check color_at(spot) == red
    me.draw_voxel(vec3(3, 0, 0), blue)
    me.stop()
    check color_at(vec3(3, 0, 0)) == blue
    me.frames.clear()

  test "mesh options read back":
    check me.sealed_frames
    me.sealed_frames = false
    check not me.sealed_frames
    me.sealed_frames = true
    check not me.cull_down_faces
    me.cull_down_faces = true
    check me.cull_down_faces
    me.cull_down_faces = false

test_summary()
