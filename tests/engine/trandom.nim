import enu/[types, base_api]
import pkg/print

let unit = Unit()
register_active(unit)
unit.seed = 122341

let f: float = 1 .. 100
echo "float: ", f
var position = vec3(1.0, 1.0, 1.0)

position =
  vec3(
    position.x + -2.0 .. 2.0, position.y + -2.0 .. 2.0, position.z + -2.0 .. 2.0
  )
echo position
