## Failing reproduction for the ASAP-toggle render race.
##
## With the current `wall` (using `advance` instead of `forward`) the
## script never re-enters ASAP, so this test draws boxes inside an
## explicit `speed = 0` / `speed = 1` toggle to reproduce the bug
## directly.
##
## At each toggle iteration:
##   1. `speed = 0` → begin_asap (renderer buffer reset).
##   2. `box(...)` writes voxels into pending_chunks.
##   3. `speed = 1` → end_asap (flush pending → chunk_deltas; paste
##      buffer to voxel_tool).
##
## Bug: after the toggles, the model store has all expected voxels
## (`has_block_at` reports them), but `voxel_tool.get_voxel`
## (queried via `rendered_block_at`) is missing some — same chunks
## that the model shows. Works correctly if speed is constant for
## the whole script.

import testing

speed = 1

# Mirrors the `asap_wall_mode=true` user-reported bug pattern:
#  - a non-ASAP write (the box).
#  - then enter ASAP via speed=0.
#  - an ASAP write (the forward, which drops voxels per step in
#    build mode at speed=0).
#  - exit ASAP via speed=1 — paste runs and used to wipe the
#    pre-ASAP voxels because the godot_voxel paste binding doesn't
#    let us request use_mask=true with mask_value=0.
5.times(i):
  box(
    width = 4, height = 4, depth = 4,
    at = vec3((i * 8).float, 0.0, 0.0),
    color = white,
  )
  speed = 0
  Build(active_unit()).advance 1.0
  speed = 1

sleep 3.0  # let chunks load + buffer paste settle

suite "ASAP toggle render race":
  test "renderer matches model after 5 ASAP toggles":
    var model_count = 0
    let origin = me.position
    # Walk a generous AABB covering all 5 cube positions. Boxes extend
    # +X/+Y/+Z from `at`, so z range is 0..3.
    for x in -1 .. 36:
      for y in -1 .. 4:
        for z in -1 .. 4:
          let pos = origin + vec3(x.float, y.float, z.float)
          if has_block_at(pos): model_count.inc
    let rendered = me.rendered_voxel_count_get
    echo "model=", model_count, " rendered=", rendered
    check model_count == 5 * 4 * 4 * 4
    check rendered >= model_count  # may include default block at (0,0,0)

test_summary()
