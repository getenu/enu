import testing, builds_private

speed = 0

let
  here = me.position
  spot = vec3(1, 0, 0)
  hand = vec3(2, 0, 0)

proc color_at(offset: Vector3): Color =
  block_color_at(here + offset)

suite "Frame Animation":
  test "save writes the current frame":
    me.clear_frames()
    me.draw_voxel(spot, red)
    check me.save() == 0
    me.draw_voxel(spot, green)
    check save() == 0 # bare form; overwrites rather than adding
    check me.frame_count == 1

  test "save(n) one past the last frame adds it and makes it current":
    check me.save(1) == 1
    check me.frame == 1
    check me.frame_count == 2

  test "frame = n loads the frame's blocks":
    me.frame = 0
    me.draw_voxel(spot, blue)
    me.frame = 1
    check color_at(spot) == green
    check me.frame == 1

  test "frames keep blocks placed by hand":
    me.frame = 0
    me.place_block(hand, red)
    save()
    me.frame = 1
    check not has_block_at(here + hand)
    me.frame = 0
    check color_at(hand) == red

  test "an unsaved frame keeps the blocks":
    me.frame = 5
    check color_at(spot) == green
    check color_at(hand) == red
    check me.frame == 5
    check me.frame_count == 2

  test "frames can have gaps":
    save()
    check me.frame_count == 3
    check me.last_frame == 5
    me.frame = 1
    check color_at(spot) == green

  test "frames past 63 raise":
    var raised = false
    try:
      me.frame = 64
    except CatchableError:
      raised = true
    check raised

  test "playing over a gap raises right away":
    var message = ""
    try:
      me.play()
    except CatchableError as e:
      message = e.msg
    check "Animation missing frame 2" in message
    me.play(first = 0, last = 1)
    me.stop()
    me.play(first = 5, last = 5)
    me.stop()

  test "clear_frame leaves a gap":
    me.clear_frame(0)
    check me.frame_count == 2
    check me.last_frame == 5
    me.frame = 1
    check color_at(spot) == green

  test "delete_frame moves later frames down":
    # frames 1 and 5 are saved; deleting the gap at 0 moves them to 0 and 4
    me.delete_frame(0)
    check me.frame_count == 2
    check me.last_frame == 4
    me.frame = 0
    check color_at(spot) == green
    check not has_block_at(here + hand)
    me.frame = 4
    check color_at(hand) == red

  test "clear_frames drops everything and goes back to frame 0":
    me.clear_frames()
    check me.frame_count == 0
    check me.last_frame == -1
    check me.frame == 0

  test "play only changes the display":
    me.draw_voxel(spot, red)
    save(0)
    me.draw_voxel(spot, green)
    save(1)
    me.play(fps = 5.0)
    sleep(0.5)
    check me.frame == 1
    me.frame = 0 # stops playback
    check color_at(spot) == red

test_summary()
