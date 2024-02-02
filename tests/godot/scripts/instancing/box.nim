proc vec_proc*(vec: Vector3): Vector3 =
  discard

name = "box"
echo "in script"
def box(length = 10, height = 20):
  echo "box", " ", "box 2"
  height.times:
    4.times:
      forward length
      turn_right()

echo "v1 ", vec_proc(vec3(1.0, 2.0, 3.0))
var v2 = Vector3()
v2.x = 1.0
v2.y = 2.0
v2.z = 3.0
echo "v2 ", vec_proc(v2)
20.times:
  box()
  forward()
