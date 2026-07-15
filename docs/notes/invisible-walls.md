# Invisible walls — `invisible` color + `swap_color`

Status: **first cut, needs in-world visual/physics verification.** The color and
`swap_color` logic are unit/world-test verified at the model level; the
rendering (does it actually draw nothing?), collision (does the player actually
stop?), and aim suppression (does the target actually not appear?) were written
carefully against the engine config but **could not be visually verified this
session** (the `loops` level wouldn't launch locally). Verify those three in the
morning; everything is structured so they're easy to tweak.

## What it does

Build an invisible wall by drawing it in a spare colour, then swapping that
colour to `invisible`:

```nim
color = green
wall length = 20, height = 10   # or any shape, in a colour unused elsewhere
swap_color(green, invisible)     # recolours every green block, computed + manual
```

`invisible` renders as nothing but still collides, so it keeps players off the
water / inside the play area. The aim target never appears on it.

## Design decisions (and why)

- **`invisible` is a named colour** (`Colors.INVISIBLE`, appended last so the
  0..6 → library-slot mapping is unchanged; INVISIBLE is slot 7). Its sentinel
  RGBA is `(0, 0, 0, 0.5)` — a **0.5 alpha** that ERASER (alpha 0) and the
  opaque named colours don't use, and that a normal opaque draw can't produce,
  so it never hijacks a user's colour via `action_index`. VM constant is
  `invisible` (`share/vmlib/enu/types.nim`), host is `ACTION_COLORS[INVISIBLE]`
  (`src/models/colors.nim`).

- **Rendering = geometry + a dedicated ALPHA=0 material.** There is no engine
  "collision but no mesh" path (`set_geometry_type` couples them:
  `GEOMETRY_CUBE` ⇒ collision, `GEOMETRY_NONE` ⇒ none). So INVISIBLE's library
  voxel (`BuildNode.tscn` slot 7, `SubResource(18)`) is a normal collidable cube
  whose `material_id = 7` points at a new material
  (`terrain_voxel_invisible.shader`) that forces `ALPHA = 0.0` — geometry meshes
  (collision generates) but nothing draws. The shader declares the `emission` /
  `emission_energy` uniforms `BuildNode` pokes so material setup doesn't hit a
  missing param. `set_visibility` was changed to **skip slot 7** so it doesn't
  overwrite the invisible shader when toggling build visibility.

  **`transparency_index` MUST be 0 (opaque for culling).** The blocky mesher
  (`voxel_mesher_blocky.cpp:30`) emits a face only when the neighbor is empty or
  has a *higher* transparency_index. The `air` voxel (slot 0) is a non-empty cube
  with `transparency_index = 1`; a first attempt gave INVISIBLE the same index,
  so every face against air was culled → **zero geometry → no collision and
  nothing to draw** (looked invisible, but you fell/walked straight through).
  With index 0, faces against air (index 1 > 0) emit, so the wall has a real
  collision shell. Invisibility comes entirely from the ALPHA=0 material, not the
  culling class. (Tradeoff: a *visible* block drawn directly against an invisible
  one culls its shared face — a gap — so keep invisible walls as their own builds
  / not interleaved with visible geometry.)

- **Collision = normal layer (mask bit 1), same as solid blocks.** The player
  collides with invisible walls exactly like any wall. (I did *not* use the
  `air` voxel's bit-31 layer trick — the `collision_mask` semantics vs the aim
  ray's mask `524309` didn't add up on inspection, so I avoided depending on
  them.)

- **Aim suppression = voxel query, not a collision-layer trick.** In
  `AimTarget.update` the ray still hits the wall (it collides), so we sample the
  voxel just inside the hit face; if it's INVISIBLE we hide the sprite, drop the
  hover, and return without setting a target. Chosen over the layer trick
  because it doesn't depend on the murky per-voxel collision-layer semantics.
  **Known limitation:** the ray *stops* at the invisible wall (you can't target
  a real block directly behind it). If you'd rather aim *through* invisible
  walls, the layer approach (invisible collision on a layer the aim ray's mask
  excludes) is the way — but that needs the collision-layer semantics pinned
  down first.

- **`swap_color(from, to)` is a retroactive one-shot** over the build's whole
  voxel state — computed (drawn) chunks *and* manual (hand-placed) edits. It
  flushes pending writes first (so they can't re-apply the old colour), rewrites
  every matching voxel, and re-flushes; the change syncs and re-renders like any
  edit. Future blocks drawn in `from` are **not** auto-swapped — call it again,
  or draw straight in `invisible`.

## Files

- `src/models/colors.nim` — `INVISIBLE` enum + `ACTION_COLORS` entry.
- `share/vmlib/enu/types.nim` — `invisible` VM constant.
- `src/models/voxels/store.nim` — `VoxelStore.swap_color`.
- `src/controllers/script_controllers/host_bridge.nim` — `swap_color(self: Build, …)` + registration.
- `share/vmlib/enu/builds.nim` — bridged decl + `swap_color(from, to)` template.
- `app/shaders/terrain_voxel_invisible.shader` — the ALPHA=0 material.
- `app/components/BuildNode.tscn` — slot-7 voxel + material/7 + library entry.
- `src/nodes/build_node.nim` — `invisible_material_index`; `set_visibility` skips it.
- `src/nodes/aim_target.nim` — hide the aim target on INVISIBLE voxels.
- `tests/worlds/unit-tests/{scripts,data}/swap_color_test*` + `level.json` — world test.

## Verify in the morning

1. **Renders as nothing:** draw a wall, `swap_color(…, invisible)` → it vanishes
   visually. (If it renders as a solid/black cube instead, the material routing
   is off — check that slot-7 voxels pick `material/7` and that `set_visibility`
   isn't stomping it.)
2. **Still collides:** walk into it → you stop. Drop onto an invisible floor →
   you land.
3. **No aim target:** look at it → no target sprite, no hover; toolbar clicks
   don't place onto it.
4. `nim test` + `nim test_world` (the `swap_color` world test) stay green.

## Open questions for Scott

- Aim: block-at-the-wall (current) vs aim-through to real blocks behind?
- Should `invisible` be selectable in the toolbar/UI, or script-only (current)?
- Sentinel colour `(0,0,0,0.5)` OK, or prefer a different reserved value?
