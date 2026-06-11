import std/[strutils, math]
import types, base_api, vm_bridge_utils

type BoxPivot* = enum
  corner
  centre
  bottom_centre

bridged_to_host:
  proc drawing*(self: Build): bool
  proc `drawing=`*(self: Build, drawing: bool)
  proc initial_position(self: Build): Vector3
  proc save*(self: Build, name = "default")
  proc restore*(self: Build, name = "default")
  proc draw_position*(self: Build): Vector3
  proc `draw_position=`*(self: Build, value: Vector3)
  proc has_block_at*(position: Vector3): bool
  proc block_color_at*(position: Vector3): Colors
  proc begin_asap*(self: Build)
  proc end_asap*(self: Build)
  proc draw_voxel*(self: Build, position: Vector3, color: Colors)
    ## Paints a COMPUTED block at the given position. Re-runs of the script
    ## regenerate it, so it isn't persisted to the save file. Used by
    ## place (the box/sphere/cylinder primitives draw host-side). For
    ## persistent placement (eg. user edits via eval, holes for windows) use
    ## place_block from builds_private, which marks the voxel MANUAL.

  proc save_level_now*()
    ## Triggers an immediate level save. Used for testing persistence.

  proc reload_unit*(self: Build)
    ## Reloads the Build's voxel data from disk without stopping the script.

  proc box_impl*(
    self: Build,
    w: int,
    h: int,
    d: int,
    color: Colors,
    fill: bool,
    pivot: int,
    at: Vector3,
    rotation_deg: float,
    use_turtle: bool,
  )
    ## OBB scan-converter primitive. User code uses the `box(...)`
    ## templates below.

  proc sphere_impl*(
    self: Build,
    size: float,
    color: Colors,
    fill: bool,
    at: Vector3,
    use_turtle: bool,
  )

  proc cylinder_impl*(
    self: Build,
    size: float,
    height: int,
    color: Colors,
    fill: bool,
    at: Vector3,
    use_turtle: bool,
  )

  proc rendered_voxel_count_get*(self: Build): int

  proc advance*(self: Build, steps: float)
    ## Translate the turtle by `steps` along its current forward
    ## direction without going through `begin_move`. No drawing, no
    ## animation, no speed/ASAP interaction. Used by `wall` / `floor`
    ## to leave the turtle at the far end of the shape.

template asap*(body: untyped) =
  ## Execute build commands instantly without incremental updates.
  let self = Build(active_unit())
  let prev_speed = self.speed
  self.speed = ASAP
  try:
    body
  finally:
    self.speed = prev_speed

proc `draw_position=`*(self: Build, unit: Unit) =
  self.draw_position = unit.position

proc go_home*(self: Build) =
  self.rotation = 0
  self.scale = 1
  self.glow = 0
  self.forward self.position.z - self.start_position.z, 2
  self.left self.position.x - self.start_position.x, 2
  self.down self.position.y - self.start_position.y, 2

proc fill_square*(self: Build, length = 1) =
  for l in 0 .. length:
    for i in 0 .. 3:
      self.forward(length - l, 2)
      self.right(1, 2)

proc place*(self: Build, x, y, z: int, color: Colors) =
  ## Place a single block at local integer coordinates.
  self.draw_voxel((x.float, y.float, z.float), color)

template place*(x, y, z: int, color: Colors) =
  ## Place a single block at local integer coords in a build script.
  Build(active_unit()).place(x, y, z, color)

# === Turtle-aware shape primitives ==================================
#
# `box`, `sphere`, `cylinder` all default to the turtle's current
# transform; pass `at = vec3(...)` to override with an explicit
# unit-local coord. `box` additionally accepts `rotation` (around Y)
# and a `pivot` (corner / centre / bottom_centre) when not using the
# turtle's basis. Default pivots: box = corner (back-bottom-left in
# turtle-local), sphere = centre, cylinder = centre-of-bottom-face.
#
# `wall` and `floor` are thin wrappers that draw a 1-thick box and
# leave the turtle at the far end (matches `forward length`), so they
# chain naturally into polygon walks.

# ---- box -----------------------------------------------------------

proc box*(
    self: Build,
    width, height, depth: int,
    color: Colors,
    fill = true,
    pivot: BoxPivot = corner,
) =
  ## At the turtle's current transform.
  self.box_impl(
    width, height, depth, color, fill, ord(pivot), vec3(0, 0, 0), 0.0, true
  )

proc box*(
    self: Build,
    width, height, depth: int,
    at: Vector3,
    color: Colors,
    rotation = 0.0,
    fill = true,
    pivot: BoxPivot = corner,
) =
  ## At an explicit unit-local coord. Optional yaw rotation.
  self.box_impl(
    width, height, depth, color, fill, ord(pivot), at, rotation, false
  )

proc box*(self: Build, at, to: Vector3, color: Colors, fill = true) =
  ## Axis-aligned corner-to-corner, inclusive of both corners. Corner
  ## order doesn't matter (min/max normalised).
  let lo = vec3(min(at.x, to.x), min(at.y, to.y), min(at.z, to.z))
  let hi = vec3(max(at.x, to.x), max(at.y, to.y), max(at.z, to.z))
  let w = int(hi.x - lo.x) + 1
  let h = int(hi.y - lo.y) + 1
  let d = int(hi.z - lo.z) + 1
  # at-mode CORNER pivot extends +X / +Y / +Z from the anchor, so
  # anchor at the min corner to cover the requested range.
  self.box_impl(
    w, h, d, color, fill, ord(corner), lo, 0.0, false
  )

template box*(
    width, height, depth: int,
    color: Colors,
    fill = true,
    pivot: BoxPivot = corner,
) =
  Build(active_unit()).box(width, height, depth, color, fill, pivot)

template box*(
    width, height, depth: int,
    at: Vector3,
    color: Colors,
    rotation = 0.0,
    fill = true,
    pivot: BoxPivot = corner,
) =
  Build(active_unit()).box(
    width, height, depth, at, color, rotation, fill, pivot
  )

template box*(at, to: Vector3, color: Colors, fill = true) =
  Build(active_unit()).box(at, to, color, fill)

# ---- sphere --------------------------------------------------------
#
# `size` = diameter in voxels. Rasterisation is centred on the target
# voxel, so the effective width is always odd: size 4 and size 5 both
# span 5 voxels (5 is fuller at the diagonals). Fractional sizes are
# allowed — useful for smooth tapers (stacked-disk cones, spires).
# Int and float sizes both accepted.

proc sphere*(self: Build, size: float, color: Colors, fill = true) =
  self.sphere_impl(size, color, fill, vec3(0, 0, 0), true)

proc sphere*(self: Build, size: float, at: Vector3, color: Colors, fill = true) =
  self.sphere_impl(size, color, fill, at, false)

proc sphere*(self: Build, size: int, color: Colors, fill = true) =
  self.sphere(size.float, color, fill)

proc sphere*(self: Build, size: int, at: Vector3, color: Colors, fill = true) =
  self.sphere(size.float, at, color, fill)

template sphere*(size: int | float, color: Colors, fill = true) =
  Build(active_unit()).sphere(size, color, fill)

template sphere*(size: int | float, at: Vector3, color: Colors, fill = true) =
  Build(active_unit()).sphere(size, at, color, fill)

# ---- cylinder ------------------------------------------------------
#
# Same `size` semantics as sphere (diameter, voxel-centred, fractional
# allowed). `height` counts voxels along the axis.

proc cylinder*(
    self: Build, size: float, height: int, color: Colors, fill = true
) =
  self.cylinder_impl(size, height, color, fill, vec3(0, 0, 0), true)

proc cylinder*(
    self: Build, size: float, height: int, at: Vector3, color: Colors,
    fill = true,
) =
  self.cylinder_impl(size, height, color, fill, at, false)

proc cylinder*(
    self: Build, size: int, height: int, color: Colors, fill = true
) =
  self.cylinder(size.float, height, color, fill)

proc cylinder*(
    self: Build, size: int, height: int, at: Vector3, color: Colors,
    fill = true,
) =
  self.cylinder(size.float, height, at, color, fill)

template cylinder*(size: int | float, height: int, color: Colors, fill = true) =
  Build(active_unit()).cylinder(size, height, color, fill)

template cylinder*(
    size: int | float, height: int, at: Vector3, color: Colors, fill = true
) =
  Build(active_unit()).cylinder(size, height, at, color, fill)

# ---- wall / floor --------------------------------------------------

template wall*(
    length: int, height: int = 4, color: Colors = active_unit().color
) =
  ## A `length`-long, `height`-tall, 1-thick wall extending along the
  ## turtle's local forward. Leaves the turtle at the wall's last
  ## voxel (advance length - 1), so `wall N; turn right; wall M`
  ## traces a closed N×M corner — the two walls share the corner
  ## voxel instead of leaving a 1-cell gap.
  let me = Build(active_unit())
  me.box(1, height, length, color)
  if length > 1:
    me.advance (length - 1).float

template floor*(
    length: int, width: int = length, color: Colors = active_unit().color
) =
  ## A `length`-deep, `width`-wide, 1-thick slab in the turtle's
  ## horizontal plane. Leaves the turtle at the slab's far edge
  ## (advance length - 1), matching `wall`.
  let me = Build(active_unit())
  me.box(width, 1, length, color)
  if length > 1:
    me.advance (length - 1).float
