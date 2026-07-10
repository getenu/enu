import std/[strutils, math]
## Commands for building with blocks: shapes like `box`, `ball`, `wall`
## and `floor`, plus turtle controls like `drawing` and `save`/`restore`.

import core, vm_bridge_utils

type BoxPivot* = enum
  corner
  centre
  bottom_centre

bridged_to_host:
  proc drawing*(self: Build): bool
    ## Whether the turtle draws blocks as it moves. `drawing = false`
    ## lets you sneak the turtle somewhere without leaving a trail.

  proc `drawing=`*(self: Build, drawing: bool)
  proc initial_position(self: Build): Vector3
  proc pen*(self: Build): Pen
    ## The drawing context — turtle pose, color, pen-down state. Capture
    ## with `var spot = pen`, return with `pen = spot`.
  proc `pen=`*(self: Build, value: Pen)

  proc draw_position*(self: Build): Vector3
    ## Where the turtle is. Assign a position (or a thing) to teleport
    ## the turtle there and keep drawing.

  proc `draw_position=`*(self: Build, value: Vector3)
  proc has_block_at*(position: Vector3): bool
    ## `true` if this build has a block at that spot.

  proc block_color_at*(position: Vector3): Color
    ## The color of the block at that spot.
  proc begin_asap*(self: Build)
  proc end_asap*(self: Build)
  proc draw_voxel*(self: Build, position: Vector3, color: Color)
    ## Paints a TRANSIENT block at the given position. Re-runs of the script
    ## regenerate it, so it isn't persisted to the save file. Used by
    ## place (the box/sphere/cylinder primitives draw host-side). For
    ## persistent placement (eg. user edits via eval, holes for windows) use
    ## place_block from builds_private, which marks the voxel PERSISTED.

  proc save_level_now*()
    ## Triggers an immediate level save. Used for testing persistence.

  proc reload_thing*(self: Build)
    ## Reloads the Build's voxel data from disk without stopping the script.

  proc box_impl*(
    self: Build,
    w: int,
    h: int,
    d: int,
    color: Color,
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
    color: Color,
    fill: bool,
    at: Vector3,
    use_turtle: bool,
  )

  proc cylinder_impl*(
    self: Build,
    size: float,
    height: int,
    color: Color,
    fill: bool,
    at: Vector3,
    use_turtle: bool,
  )

  proc save_frame_impl*(self: Build, at: int): int

  proc delete_frame*(self: Build, index: int)
    ## Remove a saved frame; later frames shift down one index.

  proc clear_frames*(self: Build)
    ## Drop every saved frame and stop playback. Frames persist across
    ## script re-runs (that's the hand-edit flow: pose, run a script that
    ## calls save, repeat) — so programmatic animations clear first.
    ## save raises after 64 frames without a clear.

  proc load_frame*(self: Build, index: int)
    ## Restore a saved frame into the live voxels for editing (this changes
    ## the real state, unlike `frame=` which only changes the display).

  proc `frame=`*(self: Build, index: int)
    ## Display a saved frame (-1 = the live voxel state). Display-only.

  proc frame*(self: Build): int

  proc frames_len*(self: Build): int

  proc play_impl*(self: Build, fps: float, loop: bool)

  proc stop_impl*(self: Build)

  proc sealed_frames*(self: Build): bool
    ## Frame meshes bake self-contained (no cross-chunk face culling):
    ## chunks on different animation frames can never show seams. On by
    ## default; turn off for fewer quads and exact border lighting when
    ## the whole animation stays in lockstep.
  proc `sealed_frames=`*(self: Build, value: bool)

  proc greedy*(self: Build): bool
    ## Greedy meshing: merge coplanar, uniformly-shaded cube faces into
    ## larger quads. On by default (identical render, less geometry);
    ## `greedy = false` opts a build out.
  proc `greedy=`*(self: Build, value: bool)

  proc cull_down_faces*(self: Build): bool
    ## Sheet hint: skip downward faces when meshing — an ocean slab's
    ## underside is never visible but costs ~a third of its geometry.
    ## Set it before drawing or playing frames.
  proc `cull_down_faces=`*(self: Build, value: bool)

  proc rendered_voxel_count_get*(self: Build): int

  proc pending_block_updates_get*(self: Thing): int
    ## Unfinished voxel pipeline work (queued, in-flight, or awaiting
    ## apply) for the thing and its descendants. 0 = every submitted edit
    ## is meshed and visible.

  proc advance*(self: Build, steps: float)
    ## Translate the turtle by `steps` along its current forward
    ## direction without going through `begin_move`. No drawing, no
    ## animation, no speed/ASAP interaction. Used by `wall` / `floor`
    ## to leave the turtle at the far end of the shape.

template frame_count*(self: Build): int =
  self.frames_len

proc save*(self: Build, at: int = -1): int {.discardable.} =
  ## Snapshot the current voxels as an animation frame and return its
  ## index — appended by default, or overwriting frame `at`. Replace
  ## workflow: load_frame(3), edit, save(at = 3). Raises past 64
  ## frames without a clear_frames().
  self.save_frame_impl(at)

proc play*(self: Build, fps = 8.0, loop = true) =
  ## Cycle through the saved frames at `fps` (loops by default).
  self.play_impl(fps, loop)

proc stop*(self: Build) =
  ## Stop frame playback; the display stays on the current frame.
  self.stop_impl()

# bare forms for the active unit, matching the drawing API
proc save*(at: int = -1): int {.discardable.} =
  Build(active_thing()).save_frame_impl(at)

proc load_frame*(index: int) =
  Build(active_thing()).load_frame(index)

proc delete_frame*(index: int) =
  Build(active_thing()).delete_frame(index)

proc clear_frames*() =
  Build(active_thing()).clear_frames()

proc play*(fps = 8.0, loop = true) =
  Build(active_thing()).play_impl(fps, loop)

proc stop*() =
  Build(active_thing()).stop_impl()

# no bare frame_count(): it would collide with the engine's global frame
# counter in base_bridge — use me.frame_count

proc pending_block_updates*(self: Thing): int =
  ## How many block changes are still being worked on. `0` means
  ## everything you've drawn is actually on screen.
  pending_block_updates_get(self)

template asap*(body: untyped) =
  ## Draw everything inside the block instantly, instead of block by
  ## block. Like `speed = ASAP`, but it puts the speed back afterward.
  let self = Build(active_thing())
  let prev_speed = self.speed
  self.speed = ASAP
  try:
    body
  finally:
    self.speed = prev_speed

proc `draw_position=`*(self: Build, thing: Thing) =
  self.draw_position = thing.position

proc go_home*(self: Build) =
  ## Head back to the start position by going forward, left, and down
  ## the right amounts. Also resets rotation, scale and glow.
  self.rotation = 0
  self.scale = 1
  self.glow = 0
  self.forward self.position.z - self.start_position.z, 2
  self.left self.position.x - self.start_position.x, 2
  self.down self.position.y - self.start_position.y, 2

proc fill_square*(self: Build, length = 1) =
  ## Draw a filled square, `length` blocks on a side.
  for l in 0 .. length:
    for i in 0 .. 3:
      self.forward(length - l, 2)
      self.right(1, 2)

proc place*(self: Build, x, y, z: int, color = self.color) =
  ## Put a single block at exact coordinates, without moving the
  ## turtle. `place 3, 0, 5, red`.
  self.draw_voxel((x.float, y.float, z.float), color)

template place*(x, y, z: int, color = active_thing().color) =
  Build(active_thing()).place(x, y, z, color)

# === Turtle-aware shape primitives ==================================
#
# `box`, `sphere`, `cylinder` all default to the turtle's current
# transform; pass `at = vec3(...)` to override with an explicit
# thing-local coord. `box` additionally accepts `rotation` (around Y)
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
    color = self.color,
    fill = true,
    pivot: BoxPivot = corner,
) =
  ## Draw a box. `box 5, 3, 8` makes one 5 wide, 3 tall and 8 deep,
  ## starting where the turtle is and facing the way it faces. Or draw
  ## it somewhere else with `at = vec3(...)`, or between two corners
  ## with `box corner1, corner2`. `fill = false` makes it hollow, like
  ## a room.
  self.box_impl(
    width, height, depth, color, fill, ord(pivot), vec3(0, 0, 0), 0.0, true
  )

proc box*(
    self: Build,
    width, height, depth: int,
    at: Vector3,
    color = self.color,
    rotation = 0.0,
    fill = true,
    pivot: BoxPivot = corner,
) =
  # At an explicit thing-local coord. Optional yaw rotation.
  self.box_impl(
    width, height, depth, color, fill, ord(pivot), at, rotation, false
  )

proc box*(self: Build, at, to: Vector3, color = self.color, fill = true) =
  # Axis-aligned corner-to-corner, inclusive of both corners. Corner
  # order doesn't matter (min/max normalised).
  let lo = vec3(min(at.x, to.x), min(at.y, to.y), min(at.z, to.z))
  let hi = vec3(max(at.x, to.x), max(at.y, to.y), max(at.z, to.z))
  let w = int(hi.x - lo.x) + 1
  let h = int(hi.y - lo.y) + 1
  let d = int(hi.z - lo.z) + 1
  # at-mode CORNER pivot extends +X / +Y / +Z from the anchor, so
  # anchor at the min corner to cover the requested range.
  self.box_impl(w, h, d, color, fill, ord(corner), lo, 0.0, false)

template box*(
    width, height, depth: int,
    color = active_thing().color,
    fill = true,
    pivot: BoxPivot = corner,
) =
  Build(active_thing()).box(width, height, depth, color, fill, pivot)

template box*(
    width, height, depth: int,
    at: Vector3,
    color = active_thing().color,
    rotation = 0.0,
    fill = true,
    pivot: BoxPivot = corner,
) =
  Build(active_thing()).box(
    width, height, depth, at, color, rotation, fill, pivot
  )

template box*(at, to: Vector3, color = active_thing().color, fill = true) =
  Build(active_thing()).box(at, to, color, fill)

# ---- sphere --------------------------------------------------------
#
# `size` = diameter in voxels. Rasterisation is centred on the target
# voxel, so the effective width is always odd: size 4 and size 5 both
# span 5 voxels (5 is fuller at the diagonals). Fractional sizes are
# allowed, useful for smooth tapers (stacked-disk cones, spires).
# Int and float sizes both accepted.

proc sphere*(self: Build, size: float, color = self.color, fill = true) =
  ## Draw a sphere, `size` blocks across, centred on the turtle. Draw
  ## it somewhere else with `at = vec3(...)`. `ball` means the same
  ## thing and is more fun to say.
  self.sphere_impl(size, color, fill, vec3(0, 0, 0), true)

proc sphere*(
    self: Build, size: float, at: Vector3, color = self.color, fill = true
) =
  self.sphere_impl(size, color, fill, at, false)

proc sphere*(self: Build, size: int, color = self.color, fill = true) =
  self.sphere(size.float, color, fill)

proc sphere*(
    self: Build, size: int, at: Vector3, color = self.color, fill = true
) =
  self.sphere(size.float, at, color, fill)

template sphere*(size: int | float, color = active_thing().color, fill = true) =
  Build(active_thing()).sphere(size, color, fill)

template sphere*(
    size: int | float, at: Vector3, color = active_thing().color, fill = true
) =
  Build(active_thing()).sphere(size, at, color, fill)

# ---- ball: kid-friendly alias for sphere ---------------------------
#
# `ball 10` reads better than `sphere 10` for young builders. Same
# args as `sphere`; color defaults to the current turtle color.

template ball*(size: int | float, color = active_thing().color, fill = true) =
  ## A sphere, but friendlier. Same as `sphere`.
  Build(active_thing()).sphere(size, color, fill)

template ball*(
    size: int | float, at: Vector3, color = active_thing().color, fill = true
) =
  Build(active_thing()).sphere(size, at, color, fill)

# ---- cylinder ------------------------------------------------------
#
# Same `size` semantics as sphere (diameter, voxel-centred, fractional
# allowed). `height` counts voxels along the axis.

proc cylinder*(
    self: Build, size: float, height: int, color = self.color, fill = true
) =
  ## Draw a cylinder, `size` blocks across and `height` blocks tall,
  ## standing on the turtle's spot. Draw it somewhere else with
  ## `at = vec3(...)`. `can` means the same thing.
  self.cylinder_impl(size, height, color, fill, vec3(0, 0, 0), true)

proc cylinder*(
    self: Build,
    size: float,
    height: int,
    at: Vector3,
    color = self.color,
    fill = true,
) =
  self.cylinder_impl(size, height, color, fill, at, false)

proc cylinder*(
    self: Build, size: int, height: int, color = self.color, fill = true
) =
  self.cylinder(size.float, height, color, fill)

proc cylinder*(
    self: Build,
    size: int,
    height: int,
    at: Vector3,
    color = self.color,
    fill = true,
) =
  self.cylinder(size.float, height, at, color, fill)

template cylinder*(
    size: int | float, height: int, color = active_thing().color, fill = true
) =
  Build(active_thing()).cylinder(size, height, color, fill)

template cylinder*(
    size: int | float,
    height: int,
    at: Vector3,
    color = active_thing().color,
    fill = true,
) =
  Build(active_thing()).cylinder(size, height, at, color, fill)

# ---- can: kid-friendly alias for cylinder --------------------------
#
# `can 5, 10` reads better than `cylinder 5, 10` for young builders.
# Same args as `cylinder`; color defaults to the current turtle color.

template can*(
    size: int | float, height: int, color = active_thing().color, fill = true
) =
  ## A cylinder, but friendlier. Same as `cylinder`.
  Build(active_thing()).cylinder(size, height, color, fill)

template can*(
    size: int | float,
    height: int,
    at: Vector3,
    color = active_thing().color,
    fill = true,
) =
  Build(active_thing()).cylinder(size, height, at, color, fill)

# ---- wall / floor --------------------------------------------------

template wall*(
    length: int, height: int = 4, color: Color = active_thing().color
) =
  ## Draw a wall, `length` blocks long and `height` tall (4 unless you
  ## say), heading the way the turtle faces. The turtle ends up at the
  ## far end, so `wall 10; turn right; wall 10` makes a perfect corner.
  ## Four of those and you've got yourself a fort.
  let me = Build(active_thing())
  me.box(1, height, length, color)
  if length > 1:
    me.advance (length - 1).float

template floor*(
    length: int, width: int = length, color: Color = active_thing().color
) =
  ## Draw a flat slab, `length` deep and `width` wide (square unless
  ## you say). Like `wall`, the turtle ends up at the far edge, ready
  ## for whatever you're building next.
  let me = Build(active_thing())
  me.box(width, 1, length, color)
  if length > 1:
    me.advance (length - 1).float
