import unittest2
import core
import models/colors
import models/builds

# The terrain clips chunk loading and meshing to a unit's bounds, so a chunk
# that lands outside them never renders. These cover the two ways that broke:
# an expansion that got skipped, and the negative-coordinate case that skipped
# it (godot-nim's AABB.contains compares point.z against position.x, so the
# containment guard this used to have reported false positives on -z).

proc test_build(): Build =
  Build.init(id = "bounds_test", transform = Transform.init, color = ACTION_COLORS[BLACK])

proc covers(self: Build, chunk_id: Vector3): bool =
  ## Every corner of the chunk has to be inside the bounds, not just its origin.
  let low = chunk_id * ChunkSize
  for dx in [0.0, ChunkDim.float]:
    for dy in [0.0, ChunkDim.float]:
      for dz in [0.0, ChunkDim.float]:
        let corner = low + vec3(dx, dy, dz)
        let b = self.bounds
        if corner.x < b.position.x or corner.x > b.position.x + b.size.x or
            corner.y < b.position.y or corner.y > b.position.y + b.size.y or
            corner.z < b.position.z or corner.z > b.position.z + b.size.z:
          return false
  true

suite "Build bounds":
  test "a single chunk at the origin is covered":
    let build = test_build()
    build.reset_bounds()
    build.expand_bounds_to_chunk(vec3(0, 0, 0))
    check build.covers(vec3(0, 0, 0))

  test "negative chunk coordinates are covered on every axis":
    for chunk_id in [
      vec3(-1, 0, -1), vec3(-2, 0, -2), vec3(0, 0, -2), vec3(-4, 0, 9),
      vec3(-6, 0, -3), vec3(8, 0, -2),
    ]:
      let build = test_build()
      build.reset_bounds()
      build.expand_bounds_to_chunk(chunk_id)
      check build.covers(chunk_id)

  test "expanding never drops an earlier chunk":
    # The regression: growing toward +z used to leave a -z chunk outside.
    let build = test_build()
    build.reset_bounds()
    let chunks =
      [vec3(1, 0, -2), vec3(2, 0, -2), vec3(6, 0, -2), vec3(0, 0, 0), vec3(8, 0, 9)]
    for chunk_id in chunks:
      build.expand_bounds_to_chunk(chunk_id)
    for chunk_id in chunks:
      check build.covers(chunk_id)

  test "a -z chunk is covered when the bounds already reach further in -x":
    # The real regression. The old guard asked `low notin bounds` first, and
    # godot-nim's AABB.contains compares point.z against position.x — so once
    # the bounds reached further along -x than -z, a chunk at more-negative z
    # reported as already contained and its expansion was dropped. The unit
    # then rendered with those chunks clipped away. This is the shape the
    # tutorial-3 maze had: x down to -83 but z only to -31.
    let build = test_build()
    build.reset_bounds()
    build.expand_bounds_to_chunk(vec3(-8, 0, 0)) # push -x far out
    check build.bounds.position.x <= -49.0
    build.expand_bounds_to_chunk(vec3(0, 0, -2)) # now grow -z past it
    check build.covers(vec3(0, 0, -2))

  test "expansion is idempotent and order independent":
    let forward = test_build()
    forward.reset_bounds()
    let backward = test_build()
    backward.reset_bounds()
    let chunks = [vec3(-3, 0, -2), vec3(5, 0, 7), vec3(0, 0, -1)]
    for chunk_id in chunks:
      forward.expand_bounds_to_chunk(chunk_id)
      forward.expand_bounds_to_chunk(chunk_id) # twice: must not drift
    for i in countdown(chunks.high, 0):
      backward.expand_bounds_to_chunk(chunks[i])
    # Compared componentwise: AABB's `==` and `$` are GDNative calls, so
    # unittest2 stringifying a failed check would segfault under no_godot.
    check forward.bounds.position.x == backward.bounds.position.x
    check forward.bounds.position.y == backward.bounds.position.y
    check forward.bounds.position.z == backward.bounds.position.z
    check forward.bounds.size.x == backward.bounds.size.x
    check forward.bounds.size.y == backward.bounds.size.y
    check forward.bounds.size.z == backward.bounds.size.z

  test "the empty sentinel is negative so it can't be grown from by accident":
    check empty_bounds().size.x < 0
    check empty_bounds().size.y < 0
    check empty_bounds().size.z < 0

  test "reset_bounds rebuilds from the store's chunks":
    # A fresh build already owns the chunk holding its starting voxel, so
    # reset_bounds yields one chunk's worth: ChunkSize * 2 + 1 per axis.
    let build = test_build()
    build.reset_bounds()
    check build.bounds.size.x == ChunkDim.float * 2 + 1
    check build.covers(vec3(0, 0, 0))
