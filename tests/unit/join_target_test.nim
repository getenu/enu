import unittest2
import core
import models
import models/builds {.all.}

# Which unit a block placed by hand goes to (see join_target).

let red = ACTION_COLORS[RED]

proc unit_at(x, y, z: float, blocks: varargs[Vector3]): Build =
  ## A unit at (x, y, z) with blocks at `blocks`, local to it.
  result = Build.init(transform = Transform.init(origin = vec3(x, y, z)))
  for cell in blocks:
    result.draw(cell, (PERSISTED, red))
  state.things += result

suite "Which unit a block joins":
  setup:
    state = GameState.init
    state.player = Player.init(id = "player-me")
    last_edited = nil
    end_stroke()

  test "a block placed on a unit joins it":
    let aimed = unit_at(0, 0, 0, vec3())
    last_edited = unit_at(2, 0, 0, vec3())
    check join_target(aimed, vec3(1, 0, 0)) == aimed

  test "a block touching a unit joins it":
    let unit = unit_at(0, 0, 0, vec3())
    check join_target(nil, vec3(0, 1, 0)) == unit

  test "a corner or edge isn't touching":
    discard unit_at(0, 0, 0, vec3())
    check join_target(nil, vec3(1, 1, 0)).is_nil
    check join_target(nil, vec3(1, 1, 1)).is_nil

  test "nothing nearby starts a new unit":
    last_edited = unit_at(0, 0, 0, vec3())
    check join_target(nil, vec3(4, 0, 0)).is_nil

  test "the last edited unit wins within 2 cells":
    discard unit_at(0, 0, 0, vec3())
    last_edited = unit_at(3, 0, 2, vec3())
    check join_target(nil, vec3(1, 0, 0)) == last_edited

  test "past 2 cells, a touching unit wins":
    let touching = unit_at(0, 0, 0, vec3())
    last_edited = unit_at(4, 0, 0, vec3())
    check join_target(nil, vec3(1, 0, 0)) == touching

  test "the unit touching the most faces wins":
    discard unit_at(0, 0, 0, vec3())
    let more = unit_at(2, 0, 0, vec3(), vec3(-1, 1, 0))
    check join_target(nil, vec3(1, 0, 0)) == more

  test "a turned unit's blocks are where it shows them":
    let unit = Build.init(
      transform = Transform(basis: init_basis(0, 0, 1, 0, 1, 0, -1, 0, 0))
    )
    unit.draw(vec3(1, 0, 0), (PERSISTED, red)) # at (0, 0, -1) once turned
    state.things += unit
    check join_target(nil, vec3(0, 0, -2)) == unit
    check join_target(nil, vec3(2, 0, 0)).is_nil

  test "a unit inside another one can take blocks":
    let outer = unit_at(10, 0, 0)
    let inner = Build.init(
      transform = Transform.init(origin = vec3(0, 5, 0)), parent = outer
    )
    inner.draw(vec3(), (PERSISTED, red))
    outer.things += inner
    check join_target(nil, vec3(10, 6, 0)) == inner

  test "a locked unit never takes blocks":
    let locked = unit_at(0, 0, 0, vec3())
    locked.global_flags += LOCK
    last_edited = locked
    check join_target(locked, vec3(1, 0, 0)).is_nil
    state.player.flags += GOD
    check join_target(locked, vec3(1, 0, 0)) == locked

  test "a block with no target starts a unit the next one joins":
    place_at(vec3(10, 0, 0))
    let made = stroke.target
    let color = state.player.selected_color
    check made.voxel_info(vec3()).color == color
    check last_edited == made
    end_stroke()
    stroke.target = join_target(nil, vec3(12, 0, 0))
    check stroke.target == made
    place_at(vec3(12, 0, 0))
    check made.voxel_info(vec3(2, 0, 0)).color == color

suite "Create mode":
  setup:
    state = GameState.init
    state.player = Player.init(id = "player-me")
    state.watch_player
    last_edited = nil
    end_stroke()

  test "it only turns on with a block tool":
    state.player.tool = CODE_MODE
    state.set_create_mode true
    check CREATE_MODE notin state.local_flags
    state.player.tool = BLUE_BLOCK
    state.set_create_mode true
    check CREATE_MODE in state.local_flags
    state.set_create_mode true
    check CREATE_MODE in state.local_flags
    state.set_create_mode false
    check CREATE_MODE notin state.local_flags

  test "pressing the selected color again toggles it":
    state.player.tool = RED_BLOCK
    state.select_or_modify RED_BLOCK
    check CREATE_MODE in state.local_flags
    state.select_or_modify RED_BLOCK
    check CREATE_MODE notin state.local_flags

  test "leaving block mode turns it off":
    state.player.tool = BLUE_BLOCK
    state.set_create_mode true
    state.player.tool = GREEN_BLOCK
    check CREATE_MODE in state.local_flags
    state.player.tool = CODE_MODE
    check CREATE_MODE notin state.local_flags

  test "a block next to a unit starts a new one, then it turns off":
    let unit = unit_at(0, 0, 0, vec3())
    state.player.tool = BLUE_BLOCK
    state.set_create_mode true
    stroke.creating = true
    place_at(vec3(1, 0, 0))
    check stroke.target != unit
    check last_edited == stroke.target
    check vec3(1, 0, 0) notin unit
    check CREATE_MODE notin state.local_flags

  test "a block on a unit's face starts a new one":
    let unit = unit_at(0, 0, 0, vec3())
    state.player.tool = BLUE_BLOCK
    state.set_create_mode true
    anchor_stroke(STROKE_PLACE, unit.id, vec3(0, 1, 0), UP, vec3(0, 0.5, 0))
    stroke.creating = CREATE_MODE in state.local_flags
    unit.paint_cell(vec3(0, 1, 0), endpoint = true)
    check vec3(0, 1, 0) notin unit
    check stroke.target != unit
    check stroke.target.voxel_info(vec3()).color == state.player.selected_color
