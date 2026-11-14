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
    state.player.tool = BLUE_BLOCK
    last_edited = nil
    aim_join = nil
    create_choice = CREATE_AUTO
    create_held = false
    end_stroke()

  proc place(cell: Vector3) =
    ## A click on the ground at `cell`, as Ground.fire does it.
    stroke.target = next_block(join_target(nil, cell))
    stroke.creating = stroke.target.is_nil
    place_at(cell)
    end_stroke()

  test "it shows on when no unit would take the block":
    let unit = unit_at(0, 0, 0, vec3())
    check aim_at(nil, vec3(1, 0, 0)) == unit
    check CREATE_MODE notin state.local_flags
    check aim_at(nil, vec3(10, 0, 0)).is_nil
    check CREATE_MODE in state.local_flags

  test "it's only for the block tools":
    state.player.tool = CODE_MODE
    discard aim_at(nil, vec3(10, 0, 0))
    check CREATE_MODE notin state.local_flags
    state.set_create_mode true
    check CREATE_MODE notin state.local_flags

  test "turned on, the next block starts a unit wherever it is":
    let unit = unit_at(0, 0, 0, vec3())
    discard aim_at(nil, vec3(1, 0, 0))
    state.set_create_mode true
    check CREATE_MODE in state.local_flags
    check aim_at(unit, vec3(0, 1, 0)).is_nil
    check aim_at(nil, vec3(1, 0, 0)).is_nil
    place(vec3(1, 0, 0))
    check vec3(1, 0, 0) notin unit
    check last_edited != unit

  test "once it has started a unit, the rules decide again":
    discard unit_at(0, 0, 0, vec3())
    discard aim_at(nil, vec3(1, 0, 0))
    state.set_create_mode true
    place(vec3(1, 0, 0))
    let made = last_edited
    check create_choice == CREATE_AUTO
    check aim_at(nil, vec3(2, 0, 0)) == made
    check CREATE_MODE notin state.local_flags

  test "turned off, blocks join the last edited unit however far":
    last_edited = unit_at(0, 0, 0, vec3())
    let unit = last_edited
    check aim_at(nil, vec3(10, 0, 0)).is_nil
    state.set_create_mode false
    check CREATE_MODE notin state.local_flags
    check aim_at(nil, vec3(10, 0, 0)) == unit
    place(vec3(10, 0, 0))
    check vec3(10, 0, 0) in unit
    check aim_at(nil, vec3(20, 0, 0)) == unit
    place(vec3(20, 0, 0))
    check vec3(20, 0, 0) in unit
    check create_choice == CREATE_OFF

  test "turned off, an aimed unit still takes the block":
    last_edited = unit_at(0, 0, 0, vec3())
    let other = unit_at(10, 0, 0, vec3())
    discard aim_at(nil, vec3(5, 0, 0))
    state.set_create_mode false
    check aim_at(other, vec3(10, 1, 0)) == other

  test "it can't turn off with no unit to join":
    check aim_at(nil, vec3(10, 0, 0)).is_nil
    state.set_create_mode false
    check CREATE_MODE in state.local_flags
    check create_choice == CREATE_AUTO

  test "turned off, a locked last edited unit hands back to the rules":
    last_edited = unit_at(0, 0, 0, vec3())
    discard aim_at(nil, vec3(10, 0, 0))
    state.set_create_mode false
    last_edited.global_flags += LOCK
    check aim_at(nil, vec3(10, 0, 0)).is_nil
    check create_choice == CREATE_AUTO
    check CREATE_MODE in state.local_flags

  test "turning it back, the rules decide again":
    let unit = unit_at(0, 0, 0, vec3())
    discard aim_at(nil, vec3(1, 0, 0))
    state.set_create_mode true
    state.set_create_mode false
    check create_choice == CREATE_AUTO
    check aim_at(nil, vec3(1, 0, 0)) == unit

  test "holding Cmd/Ctrl starts a unit while it's held":
    let unit = unit_at(0, 0, 0, vec3())
    create_held = true
    check aim_at(unit, vec3(0, 1, 0)).is_nil
    check CREATE_MODE in state.local_flags
    create_held = false
    check aim_at(unit, vec3(0, 1, 0)) == unit
    check CREATE_MODE notin state.local_flags

  test "a block on a unit's face starts a new one":
    let unit = unit_at(0, 0, 0, vec3())
    discard aim_at(unit, vec3(0, 1, 0))
    state.set_create_mode true
    anchor_stroke(STROKE_PLACE, unit.id, vec3(0, 1, 0), UP, vec3(0, 0.5, 0))
    stroke.target = next_block(join_target(unit, vec3(0, 1, 0)))
    stroke.creating = stroke.target.is_nil
    unit.paint_cell(vec3(0, 1, 0), endpoint = true)
    check vec3(0, 1, 0) notin unit
    check stroke.target != unit
    check stroke.target.voxel_info(vec3()).color == state.player.selected_color

  test "pressing the selected color again toggles it":
    let unit = unit_at(0, 0, 0, vec3())
    discard aim_at(unit, vec3(0, 1, 0))
    state.select_or_modify BLUE_BLOCK
    check CREATE_MODE in state.local_flags
    state.select_or_modify BLUE_BLOCK
    check CREATE_MODE notin state.local_flags
    state.select_or_modify RED_BLOCK
    check state.player.tool == RED_BLOCK

  test "another color keeps it; another tool hands back to the rules":
    let unit = unit_at(0, 0, 0, vec3())
    discard aim_at(unit, vec3(0, 1, 0))
    state.set_create_mode true
    state.player.tool = GREEN_BLOCK
    check create_choice == CREATE_ON
    state.player.tool = CODE_MODE
    check create_choice == CREATE_AUTO
    check CREATE_MODE notin state.local_flags
