# Scaled units cull (disappear) sooner than full-size ones

## Symptom
A unit at `scale = 0.25` disappears ~4× sooner than a `scale = 1` unit when the
player walks away. Suspected to be `VoxelTerrain` / view-distance, not a general
godot material/culling thing.

## Key finding: the compensation already exists
`BuildNode` **is** the `VoxelTerrain`, and `max_view_distance` is measured in
**local voxels**. The node's `scale` shrinks those voxels in world space, so the
world-space view distance scales with `scale` unless compensated.

`src/nodes/build_node.nim:273-279` already compensates:

```nim
self.model.scale_value.watch:
  if added:
    self.max_view_distance = int(self.default_view_distance.float / change.item)
```

`default_view_distance` is captured at node `init` (line 36) from the scene's
`max_view_distance`. The math is correct and in the right direction:
`scale 0.25 → max_view_distance = default × 4 → × 0.25 world = default`. So in
principle a scaled build should cull at the *same* world distance as a full-size
one.

## So the real question: why does it fall short?
Two candidates, predicting different fixes:

1. **`VoxelTerrain` clamps `max_view_distance` (prime suspect).** godot_voxel
   bounds this value to a hard ceiling. If `default ÷ scale` overshoots the cap,
   it's silently clamped → small scales get only *partial* compensation and
   still cull early (matches "disappears sooner," just not the full 4×). With
   `default` captured from the scene, a moderately-high default + `÷0.25` could
   already exceed the cap.

2. **Only fires from the `scale_value.watch`** (weaker candidate). The watch
   fires on scale *changes*; a unit **loaded already-scaled** (persisted scale,
   or scale set during construction before the node/watch exist) might never
   trigger it. Loaded units *do* get their transform applied (hinting watches
   replay the current value), so this is the less likely of the two — but worth
   confirming for `scale` specifically.

## Next step to disambiguate (one diagnostic)
Log what `max_view_distance` is *assigned* vs what it *reads back* after the
assignment, for a scaled unit:
- assigned ≠ read-back → **clamp** (candidate 1). The engine cap is then the real
  floor on how small a unit can get before early culling; extending
  `max_view_distance` past the cap isn't possible, so tiny units need a different
  strategy.
- not firing at all → **watch / load-time path** (candidate 2). Fix: also apply
  the `÷scale` compensation at node setup using the current scale.

Status: investigated read-only; no diagnostic added yet (paused to pick up a
separate reload-crash reproduction).
