# Godot 4 Migration Guide

This document captures key findings and patterns from migrating Enu from Godot 3.5 to Godot 4.

## Major API Changes

### Type System Changes
- `Transform` → `Transform3D`
- `Spatial` → `Node3D` 
- All related imports must be updated accordingly

### Import Changes
```nim
# Old (Godot 3)
import pkg/godot
import godotapi/spatial

# New (Godot 4)
import gdext/classes/gdnode3d
```

### Core Type Exports
Add these exports to core.nim for Godot 4 compatibility:
```nim
export Transform3D, Vector3, Vector2, Basis, AABB
```

## Voxel Terrain Specific Issues

### Area Editability Problem
**Issue**: `is_area_editable()` returns false, preventing voxel terrain editing.

**Root Cause**: VoxelTerrain streaming system needs time to load areas before they become editable.

**Solution**: Add a 2-second delay after VoxelTerrain initialization before testing editability:
```nim
method ready*(self: BuildNode) {.gdsync.} =
  print("[VOXEL] BuildNode ready - checking VoxelTerrain configuration...")
  self.update_at = get_mono_time() + init_duration(seconds = 2)
```

**Technical Details**: 
- `is_area_editable()` depends on `_terrain->get_storage().is_area_loaded(box)`
- The streaming system loads areas asynchronously
- Only LOD 0 areas are editable for LOD terrain
- Found in `vendor/godot/modules/voxel/edition/voxel_tool_terrain.cpp`

## Migration Patterns

### Naming Conventions
- Always use `snake_case` for variables and function names
- Use `init_hash_set()` instead of `initHashSet()`
- Use `to_flatty()` instead of `toFlatty()`
- Use `join_path()` instead of `joinPath()`

### Unresolved Migration Issues
For functions that need complex migration work, use this pattern:
```nim
proc init*(_: type Transform3D, origin = vector3()): Transform3D =
  discard
  # GD4: need to figure out how to create Transform3D with origin
```

### gcsafe Issues
Some transform methods like `rotated` are no longer gcsafe. Address these case-by-case.

## Build System

### Key Build Commands
- `nimble build_extension` - Build the Enu extension
- `nimble generate_bindings` - Generate Nim bindings for custom Godot build
- `nimble build_godot` - Build Godot with voxel module

### Extension Configuration
- Main extension file: `src/EnuGame.gdextension`
- Entry point: `bootstrap.nim`

## File Migration Progress

### Completed ✅
- **Non-Godot files migrated**: `types.nim`, `core.nim`, `models.nim`, `controllers.nim`
- **Supporting directories**: `controllers/`, `libs/`, `models/`
- **Compilation fixes**: All core data model files now compile successfully
- **Import updates**: Updated all imports from Godot 3 to Godot 4 patterns

### Next Steps 🔄
1. **Mechanically translate Godot files**: `gdutils`, `ui/*`, `nodes/*`
2. **Update bootstrap.nim**: Import everything like the original `enu.nim`
3. **Test complete build**: Verify `nimble build_extension` compiles everything

### Migration Strategy
1. Copy non-Godot files first (data models, core utilities)
2. Fix compilation errors with new type system
3. Systematically migrate Godot-specific files
4. Update bootstrap to wire everything together
5. Test full build pipeline

## Key Learnings

### Timing Issues
- VoxelTerrain requires initialization time before areas become editable
- 2-second delay resolves the editability issue

### Import Strategy
- Start with core.nim exports to establish type availability
- Update imports file-by-file following the dependency chain
- Use gdext classes instead of old godotapi imports

### Error Patterns
- Most errors relate to type name changes (Transform → Transform3D)
- Import path changes are systematic and predictable
- Some gcsafe issues require individual attention

This migration follows a systematic approach: establish core types, fix data models, then progressively migrate UI and node components.