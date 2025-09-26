# Godot 3 to 4 Migration Guide

This guide provides essential patterns and concepts for migrating Enu from Godot 3 to Godot 4, specifically using the transition from nim-godot bindings to gdext.

## Core Migration Concepts

### Object Reference Types

**gdext References (`gdref`)**
- All Godot objects in gdext are wrapped in `gdref` types
- Must be cast using `.as(gdref Type)` before accessing properties
- Must be dereferenced with `[]` to access/modify properties
- Example: `material.as(gdref StandardMaterial3D)[]` for property access

**Standard Node Types**
- Built-in Godot nodes (Control, Node, etc.) do not need dereferencing
- Access properties directly: `self.window.set_visible(true)`
- Cast standard nodes with `.as(NodeType)` without `gdref`

### Memory Management

**Property Access Patterns**
```nim
# gdref objects - need casting and dereferencing
let material = self.material.as(gdref StandardMaterial3D)
if ?material:
  material[].albedo_color = godot_color
  material[].transparency = BaseMaterial3D_Transparency.transparencyAlpha

# Standard nodes - direct access
self.window.set_visible(true)
self.button.set_text("New Text")
```

**Safe Reference Checking**
Always check references before use with the custom `?` operator:
```nim
if ?material:
  # Safe to use material
if ?self.mesh:
  # Safe to use mesh
```

### Import Changes
```nim
# Godot 3
import godotapi/[node, control, button]

# Godot 4
import gdext/classes/[gdnode, gdcontrol, gdbutton]
```

### Object Definitions
```nim
# Godot 3
gdobj MyClass of Node:

# Godot 4
type MyClass* {.gdsync.} = ptr object of Node
```

### Method Signatures
```nim
# Godot 3
method ready*() =

# Godot 4
method ready*(self: MyClass) {.gdsync.} =
```

## Signal System Migration

### Signal Connection Changes
The signal binding system changed significantly from Godot 3 to 4:

**Godot 3 Pattern (using helper function):**
```nim
# Helper function approach
self.bind_signal(button, "pressed", button.name)
self.bind_signal(option_button, "item_selected", option_button.name)
```

**Godot 4 Pattern (direct connections):**
```nim
# Direct signal connections using callable
discard self.megapixels_up.connect(
  "pressed", self.callable("_on_megapixels_up_pressed")
)
discard self.environments.connect(
  "item_selected", self.callable("_on_environments_selected")
)
```

### Signal Handler Naming
Nim doesn't allow identifiers starting with underscores, but Godot expects signal handlers to be prefixed with `_on_`. Use the `name` pragma:

```nim
# Method that Godot calls as "_on_pressed"
proc on_pressed(self: MyClass) {.gdsync, name: "_on_pressed".} =
  # Handle button press

# Handler for specific button
proc on_megapixels_up_pressed(self: Settings) {.gdsync, name: "_on_megapixels_up_pressed".} =
  self.on_pressed("MegapixelsUp")
```

### Animation System Changes

**Godot 3 Tween Pattern:**
```nim
# Single tween instance, reused
discard self.tween.interpolate_property(
  node, property, start_value, end_value,
  duration, transition, ease
)
discard self.tween.start()
```

**Godot 4 Tween Pattern:**
```nim
# Create new tween for each animation
self.tween = self.create_tween()
let tweener = self.tween[].tween_property(
  node, new_node_path(property), variant(end_value), duration
)
discard tweener[].set_trans(Tween_TransitionType(transition))
discard tweener[].set_ease(Tween_EaseType(ease))
```

## Property Access Migration

### Theme Overrides
**Godot 3:**
```nim
self.main_container.add_constant_override("margin_bottom", value)
node.add_color_override("font_color", color_value)
```

**Godot 4:**
```nim
self.main_container.add_theme_constant_override("margin_bottom", value)
node.add_theme_color_override("font_color", color_value)
```

### Node Property Access
**Godot 3:**
```nim
button.text = "New Text"
button.disabled = true
container.rect_size.y
```

**Godot 4:**
```nim
button.set_text("New Text")
button.set_disabled(true)
container.get_size().y
```

### Viewport and Scene Tree
**Godot 3:**
```nim
viewport.size.x
self.get_tree().set_input_as_handled()
```

**Godot 4:**
```nim
let viewport_rect = viewport.get_visible_rect()
viewport_rect.size.x
self.get_viewport().set_input_as_handled()
```

## Common Migration Issues

### Scene Structure Assumptions
**Problem:** Don't assume Godot 4 scene structures match what you expect from code inspection alone.

**Example Issue:**
```nim
# WRONG: Assuming AnimationTree exists because code references it
self.animation_tree = self.skin.find_child("AnimationTree", false, false).as(AnimationTree)
if ?self.animation_tree:  # Treating as "optional"
```

**Solution:**
1. **Always check the actual .tscn files** to see what nodes exist
2. **Match the Godot 3 structure** - if Godot 3 only used AnimationPlayer, Godot 4 likely should too
3. **Use assertions for required components** that must exist according to the scene

```nim
# CORRECT: Only expect what's actually in the scene
self.animation_player = self.skin.find_child("AnimationPlayer", false, false).as(AnimationPlayer)
assert ?self.animation_player, "BotNode must have an AnimationPlayer"
# No AnimationTree handling - it's not in the scene
```

**Key Insight:** Scene files are the source of truth, not code assumptions.

### Matrix Access (Basis Vectors)
**Problem:** Godot stores matrices in row-major format but movement code expects column vectors (axis vectors).

**Godot 3:**
```nim
# Direct access worked
let forward = transform.basis.z
```

**Godot 4 Solution:**
```nim
# Need helper methods to extract columns
proc get_column_z*(self: Basis): Vector3 =
  vector3(self.x.z, self.y.z, self.z.z)

let forward = transform.basis.get_column_z()
```

### String Conversion
**Godot 4 requires explicit string conversion:**
```nim
# Convert GdString to Nim string
let level_text = $self.levels.get_text()
let item_text = $self.environments.get_item_text(index.int32)
```

### Input Handling
**Method name changes:**
```nim
# Godot 3
event.is_action_pressed("ui_cancel")

# Godot 4 (same API, but different import paths)
event.is_action_pressed("ui_cancel")
```

## Migration Workflow

### Before Implementing New Functionality
**IMPORTANT:** When adding new functionality (as opposed to fixing bugs), always reference the Godot 3 version first. The goal is to match the Godot 3 logic as closely as possible, only adapting the API calls and patterns necessary for Godot 4 compatibility.

**Workflow:**
1. Locate the corresponding Godot 3 implementation in `/Users/scott/src/github.com/dsrw/enu/src/`
2. Study the logic, flow, and behavior patterns
3. Identify which parts need API adaptation for Godot 4
4. Implement the same logic using Godot 4 patterns from this guide
5. Preserve the original behavior and user experience

This approach ensures consistency between versions and reduces the risk of introducing unintended behavioral changes during migration.

## Build Validation
**CRITICAL:** Always ensure `./build.sh` returns exit code 0 before considering any migration task complete. This is the primary success criterion for all code changes.
