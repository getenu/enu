import testing

speed = 0

let here = me.position

suite "Frame Animation":
  test "save_frame returns sequential indices":
    me.draw_voxel(vec3(1, 0, 0), red)
    check me.save_frame() == 0
    me.draw_voxel(vec3(1, 0, 0), green)
    check me.save_frame() == 1
    check me.frame_count == 2

  test "load_frame restores a saved pose into the live voxels":
    me.load_frame(0)
    check block_color_at(here + vec3(1, 0, 0)) == red
    me.load_frame(1)
    check block_color_at(here + vec3(1, 0, 0)) == green

  test "frame= is display-only; live voxels keep answering queries":
    me.frame = 0
    check block_color_at(here + vec3(1, 0, 0)) == green
    me.frame = -1

  test "save_frame(at) replaces a frame in place":
    me.load_frame(0) # red pose into live voxels; display back to live
    check me.frame == -1
    me.draw_voxel(vec3(1, 0, 0), white)
    check me.save_frame(at = 0) == 0
    check me.frame_count == 2 # replaced, not appended
    me.load_frame(0)
    check block_color_at(here + vec3(1, 0, 0)) == white

  test "delete_frame removes and shifts":
    discard me.save_frame() # a third frame to delete
    check me.frame_count == 3
    me.delete_frame(2)
    check me.frame_count == 2

  test "clear_frames drops everything and stops playback":
    me.clear_frames()
    check me.frame_count == 0
    check me.frame == -1
    # rebuild two frames for the playback test below
    me.draw_voxel(vec3(1, 0, 0), red)
    discard me.save_frame()
    me.draw_voxel(vec3(1, 0, 0), green)
    discard me.save_frame()

  test "save_frame raises at the frame cap":
    while me.frame_count < 64:
      discard me.save_frame()
    var raised = false
    try:
      discard me.save_frame()
    except CatchableError:
      raised = true
    check raised
    # trim back down; playback below wants a small stack
    me.clear_frames()
    me.draw_voxel(vec3(1, 0, 0), red)
    discard me.save_frame()
    me.draw_voxel(vec3(1, 0, 0), green)
    discard me.save_frame()

  test "play_frames advances the current frame":
    me.play_frames(fps = 5.0)
    var waited = 0.0
    while me.frame < 0 and waited < 5.0:
      sleep(0.25)
      waited += 0.25
    check me.frame >= 0
    me.stop_frames()

test_summary()
