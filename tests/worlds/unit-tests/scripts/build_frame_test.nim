import testing

speed = 0

let here = me.position

suite "Frame Animation":
  test "save returns sequential indices":
    me.draw_voxel(vec3(1, 0, 0), red)
    check me.save() == 0
    me.draw_voxel(vec3(1, 0, 0), green)
    check save() == 1 # bare form, discardable
    save(at = 1) # discard-free overwrite
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

  test "save(at) replaces a frame in place":
    me.load_frame(0) # red pose into live voxels; display back to live
    check me.frame == -1
    me.draw_voxel(vec3(1, 0, 0), white)
    check me.save(at = 0) == 0
    check me.frame_count == 2 # replaced, not appended
    me.load_frame(0)
    check block_color_at(here + vec3(1, 0, 0)) == white

  test "delete_frame removes and shifts":
    discard me.save() # a third frame to delete
    check me.frame_count == 3
    me.delete_frame(2)
    check me.frame_count == 2

  test "clear_frames drops everything and stops playback":
    me.clear_frames()
    check me.frame_count == 0
    check me.frame == -1
    # rebuild two frames for the playback test below
    me.draw_voxel(vec3(1, 0, 0), red)
    discard me.save()
    me.draw_voxel(vec3(1, 0, 0), green)
    discard me.save()

  test "save raises at the frame cap":
    while me.frame_count < 64:
      discard me.save()
    var raised = false
    try:
      discard me.save()
    except CatchableError:
      raised = true
    check raised
    # trim back down; playback below wants a small stack
    me.clear_frames()
    me.draw_voxel(vec3(1, 0, 0), red)
    discard me.save()
    me.draw_voxel(vec3(1, 0, 0), green)
    discard me.save()

  test "play advances the current frame":
    me.play(fps = 5.0)
    var waited = 0.0
    while me.frame < 0 and waited < 5.0:
      sleep(0.25)
      waited += 0.25
    check me.frame >= 0
    me.stop()

test_summary()
