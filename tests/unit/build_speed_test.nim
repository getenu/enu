import unittest2
import std/[monotimes, times]
import core
import models
import models/builds {.all.}

suite "Build auto speed":
  test "builds default to auto speed":
    let build = Build.init(id = "build_auto_default")
    check build.speed == AUTO

  test "arming a ramp leaves ASAP and starts at the slow end":
    let build = Build.init(id = "build_auto_arm")
    build.arm_auto_ramp()
    check build.auto_ramp_active
    check not build.auto_ramp_started
    check not build.auto_ramp_done
    check build.voxels_per_frame == AUTO_RAMP_START_SPEED
    check ASAP_MODE notin build.global_flags

  test "the ramp eases in — slower than linear at the midpoint":
    let build = Build.init(id = "build_auto_curve")
    build.arm_auto_ramp()
    build.auto_ramp_started = true
    # Pretend half of the ramp's time has elapsed.
    build.auto_ramp_start =
      get_mono_time() + init_duration(milliseconds = -1500)
    build.update_auto_ramp()
    check build.auto_ramp_active
    let linear_mid = (AUTO_RAMP_START_SPEED + AUTO_RAMP_END_SPEED) / 2
    check build.voxels_per_frame > AUTO_RAMP_START_SPEED
    check build.voxels_per_frame < linear_mid

  test "the ramp hands off to ASAP once its time is up":
    let build = Build.init(id = "build_auto_done")
    build.arm_auto_ramp()
    build.auto_ramp_started = true
    build.auto_ramp_start = get_mono_time() + init_duration(seconds = -4)
    build.update_auto_ramp()
    check not build.auto_ramp_active
    check build.auto_ramp_done
    check build.voxels_per_frame == float.high
    check ASAP_MODE in build.global_flags

  test "an un-armed auto build stays in ASAP (level-load path)":
    let build = Build.init(id = "build_auto_unarmed")
    # No arm: update is a no-op and the build keeps ASAP's batched meshing.
    check not build.auto_ramp_active
    build.update_auto_ramp()
    check not build.auto_ramp_active
    check ASAP_MODE in build.global_flags
