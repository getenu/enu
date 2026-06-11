# Fractal tree (~16 m): recursive 3D branching with leaf clusters.
# The turtle is pitched straight up first (`lean back, 90`) so the trunk
# climbs. Each split ROLLS around the branch axis (`lean right, k * 120`)
# before pitching away from it (`lean back, ~35`) — the classic L-system
# move that spreads children evenly around the parent. Without the roll,
# all branches fork in one plane and the tree becomes a tangled vine.
scale = 0.25

proc branch(depth: int, len: int) =
  if depth == 0:
    sphere(size = 4 + (0 .. 2), color = green) # leaf cluster
    return
  color = brown
  forward len
  if depth > 4:
    # trunk: a single continuation with a slight random wander
    save()
    lean right, 0.0 .. 360.0
    lean back, 0.0 .. 8.0
    branch(depth - 1, (len.float * 0.85).int)
    restore()
  else:
    # crown: three children spread 120 degrees apart around the axis
    3.times(k):
      save()
      lean right, k.float * 120.0 + (-25.0 .. 25.0)
      lean back, 28.0 + (0.0 .. 14.0)
      branch(depth - 1, (len.float * 0.72).int)
      restore()

color = brown
lean back, 90.0 # point the turtle straight up
branch(6, 15)
