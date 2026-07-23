import unittest2
import core

suite "Stroke plane interpolation":
  test "no cells between equal or adjacent cells":
    check plane_cells_between(vec3(0, 5, 0), vec3(0, 5, 0), 1).len == 0
    check plane_cells_between(vec3(0, 5, 0), vec3(1, 5, 0), 1).len == 0

  test "straight line fills the gap":
    let cells = plane_cells_between(vec3(0, 5, 0), vec3(4, 5, 0), 1)
    check cells == @[vec3(1, 5, 0), vec3(2, 5, 0), vec3(3, 5, 0)]

  test "diagonal is 4-connected with no pinholes":
    let start = vec3(0, 5, 0)
    let finish = vec3(3, 5, 3)
    let cells = plane_cells_between(start, finish, 1)
    check cells.len == 5
    var prev = start
    for cell in cells & @[finish]:
      check abs(cell.x - prev.x) + abs(cell.z - prev.z) == 1
      prev = cell

  test "stays on the anchored plane":
    for cell in plane_cells_between(vec3(-2, 7, 3), vec3(5, 7, -4), 1):
      check cell.y == 7

  test "works on other axes":
    let x_axis = plane_cells_between(vec3(2, 0, 0), vec3(2, 3, 0), 0)
    check x_axis == @[vec3(2, 1, 0), vec3(2, 2, 0)]
    let z_axis = plane_cells_between(vec3(0, 0, 4), vec3(3, 0, 4), 2)
    check z_axis == @[vec3(1, 0, 4), vec3(2, 0, 4)]

  test "negative direction":
    let cells = plane_cells_between(vec3(3, 5, 0), vec3(0, 5, 0), 1)
    check cells == @[vec3(2, 5, 0), vec3(1, 5, 0)]
