## Process-global registry of static RGB voxel colors. Each distinct color
## gets a runtime `VoxelLibrary` entry (cube geometry, vertex-colored via the
## shared `material_id` 6 rgb material) deduped across every build. Main
## thread only — driven by the render paths in build_node.
import std/tables
import pkg/godot except print, Color
import pkg/chroma
import godotapi/[voxel_library, voxel]
import core, models/colors, gdutils

const
  RGB_MATERIAL_ID = 6
  FIRST_DYNAMIC_SLOT = 16 # 7..15 stay spare for named-palette growth
  MAX_DYNAMIC_SLOTS = 8192
  GEOMETRY_CUBE = 1
  COLLISION_MASK = 2 # matches the named cube entries in BuildNode.tscn

# Main-thread only; threadvars keep watch bodies (compiled gcsafe) happy.
var
  registry_library {.threadvar.}: VoxelLibrary
  slots {.threadvar.}: Table[Color, int64]
  next_slot {.threadvar.}: int64
  dirty {.threadvar.}: bool
  slots_warned {.threadvar.}: bool

proc register(color: Color, slot: int64) =
  debug "registering static voxel color", slot, hex = color.to_html_hex
  if registry_library.voxel_count <= slot:
    registry_library.voxel_count = slot + 1
  let voxel = registry_library.create_voxel(slot, "rgb_" & color.to_html_hex)
  voxel.color = color
  voxel.material_id = RGB_MATERIAL_ID
  voxel.geometry_type = GEOMETRY_CUBE
  var aabbs = new_array()
  aabbs.add init_aabb(vec3(0, 0, 0), vec3(1, 1, 1)).to_variant
  voxel.collision_aabbs = aabbs
  voxel.collision_mask = COLLISION_MASK
  dirty = true

proc flush_registry*() =
  ## Bake pending registrations. Must happen before any mesh task consumes a
  ## voxel id registered since the last bake — a chunk meshed against a stale
  ## library renders those voxels as air and never remeshes.
  if dirty and not registry_library.is_nil:
    registry_library.bake()
    dirty = false

proc set_registry_library*(library: VoxelLibrary) =
  ## Adopt the (scene-shared, so process-wide) library. If a fresh library
  ## instance ever shows up, re-register the known colors into it.
  if registry_library == library:
    return
  registry_library = library
  for color, slot in slots:
    register(color, slot)
  flush_registry()

proc slot_for*(color: Color): int64 =
  ## The library voxel type id for a static color, registering on first use.
  if next_slot < FIRST_DYNAMIC_SLOT:
    next_slot = FIRST_DYNAMIC_SLOT # threadvar zero-init
  if color in slots:
    return slots[color]
  if registry_library.is_nil:
    return int64(ord WHITE) # render fallback; registry not wired yet

  if next_slot >= FIRST_DYNAMIC_SLOT + MAX_DYNAMIC_SLOTS:
    if not slots_warned:
      slots_warned = true
      warn "voxel color registry full; snapping to nearest registered color"
    result = int64(ord WHITE)
    var best_dist = float32.high
    for existing, slot in slots:
      let d = color.distance(existing)
      if d < best_dist:
        best_dist = d
        result = slot
    slots[color] = result # snap once per color, not per voxel
    return

  result = next_slot
  inc next_slot
  register(color, result)
  slots[color] = result
  # Bake right away: the resolver runs while a render batch is being written,
  # and the terrain may turn those edits into mesh tasks the same frame.
  flush_registry()
