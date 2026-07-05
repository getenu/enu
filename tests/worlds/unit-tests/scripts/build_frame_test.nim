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

  test "play_frames advances the current frame":
    me.play_frames(fps = 30.0)
    sleep(1.0)
    check me.frame >= 0
    me.stop_frames()

test_summary()
