# Named colors are Color instances — equality, cycling, and static
# construction all work on the one type.
import testing
import types
import core

suite "Colors":
  test "named colors are distinct instances":
    check blue == blue
    check blue != red
    check eraser != black # transparent zero vs opaque black

  test "named colors carry their channels":
    check blue.b == 1.0'f32
    check blue.r == 0.0'f32
    check black == (0.0'f32, 0.0'f32, 0.0'f32, 1.0'f32)

  test "static colors construct as tuples":
    let coral: Color = (r: 1.0'f32, g: 0.5'f32, b: 0.31'f32, a: 1.0'f32)
    check coral != red
    check coral.g == 0.5'f32

  test "cycle works with color instances":
    var cycler = 0
    proc pick(): Color =
      result = [red, white][cycler mod 2]
      inc cycler

    check pick() == red
    check pick() == white
    check pick() == red

echo "[VM] color tests passed!"
