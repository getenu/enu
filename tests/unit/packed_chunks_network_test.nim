import std/tables
import unittest2
import pkg/[model_citizen, flatty]
import core
import types
import models/[colors, builds, packed_chunks]

from std/times import init_duration

const recv_duration = init_duration(milliseconds = 50)

var test_port = 19640

proc next_port(): string =
  result = "127.0.0.1:" & $test_port
  inc test_port

Zen.bootstrap

suite "Packed Chunks Network Sync":
  test "single voxel sync over network":
    let port = next_port()
    var
      ctx1 = ZenContext.init(id = "ctx1a")
      ctx2 = ZenContext.init(
        id = "ctx2a",
        listen_address = port,
        min_recv_duration = recv_duration,
        blocking_recv = true,
      )

    ctx2.subscribe(ctx1)

    var chunk1 = ZenTable[Vector3, VoxelInfo].init(id = "test_chunk", ctx = ctx1)
    let pos = vec3(5, 10, 15)
    let info: VoxelInfo = (Manual, action_colors[Blue])
    chunk1[pos] = info

    ctx1.boop
    ctx2.boop

    var chunk2 = ZenTable[Vector3, VoxelInfo](ctx2["test_chunk"])
    check pos in chunk2
    check chunk2[pos].kind == Manual
    check chunk2[pos].color == action_colors[Blue]

    ctx2.close

  test "multiple voxels sync over network":
    let port = next_port()
    var
      ctx1 = ZenContext.init(id = "ctx1b")
      ctx2 = ZenContext.init(
        id = "ctx2b",
        listen_address = port,
        min_recv_duration = recv_duration,
        blocking_recv = true,
      )

    ctx2.subscribe(ctx1)

    var chunk1 = ZenTable[Vector3, VoxelInfo].init(id = "test_chunk2", ctx = ctx1)

    chunk1[vec3(0, 0, 0)] = (Hole, action_colors[Eraser])
    chunk1[vec3(1, 2, 3)] = (Manual, action_colors[Red])
    chunk1[vec3(15, 15, 15)] = (Computed, action_colors[Green])

    ctx1.boop
    ctx2.boop

    var chunk2 = ZenTable[Vector3, VoxelInfo](ctx2["test_chunk2"])

    check vec3(0, 0, 0) in chunk2
    check chunk2[vec3(0, 0, 0)].kind == Hole

    check vec3(1, 2, 3) in chunk2
    check chunk2[vec3(1, 2, 3)].kind == Manual
    check chunk2[vec3(1, 2, 3)].color == action_colors[Red]

    check vec3(15, 15, 15) in chunk2
    check chunk2[vec3(15, 15, 15)].kind == Computed
    check chunk2[vec3(15, 15, 15)].color == action_colors[Green]

    ctx2.close

  test "all colors sync correctly":
    let port = next_port()
    var
      ctx1 = ZenContext.init(id = "ctx1c")
      ctx2 = ZenContext.init(
        id = "ctx2c",
        listen_address = port,
        min_recv_duration = recv_duration,
        blocking_recv = true,
      )

    ctx2.subscribe(ctx1)

    var chunk1 = ZenTable[Vector3, VoxelInfo].init(id = "test_chunk3", ctx = ctx1)

    var z = 0
    for color in Colors:
      chunk1[vec3(0, 0, z.float)] = (Manual, action_colors[color])
      inc z

    ctx1.boop
    ctx2.boop

    var chunk2 = ZenTable[Vector3, VoxelInfo](ctx2["test_chunk3"])

    z = 0
    for color in Colors:
      let pos = vec3(0, 0, z.float)
      check pos in chunk2
      check chunk2[pos].color == action_colors[color]
      inc z

    ctx2.close

  test "voxel deletion syncs over network":
    let port = next_port()
    var
      ctx1 = ZenContext.init(id = "ctx1d")
      ctx2 = ZenContext.init(
        id = "ctx2d",
        listen_address = port,
        min_recv_duration = recv_duration,
        blocking_recv = true,
      )

    ctx2.subscribe(ctx1)

    var chunk1 = ZenTable[Vector3, VoxelInfo].init(id = "test_chunk4", ctx = ctx1)
    let pos = vec3(7, 7, 7)
    chunk1[pos] = (Manual, action_colors[Blue])

    ctx1.boop
    ctx2.boop

    var chunk2 = ZenTable[Vector3, VoxelInfo](ctx2["test_chunk4"])
    check pos in chunk2

    chunk1.del(pos)

    ctx1.boop
    ctx2.boop

    check pos notin chunk2

    ctx2.close
