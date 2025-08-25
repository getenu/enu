# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Enu is a 3D sandbox environment for creating and exploring voxel worlds using a Logo-inspired programming API. It's built with Nim and the Godot game engine (v3.5), enabling users to program interactive 3D environments using Nim scripts that run in the Nim VM.

## Build Commands

### Core Development Commands
- `nimble build` - Build the main application (required after code changes)
- `nimble prereqs` - Build Godot, download fonts, generate API bindings and stdlib (first-time setup)
- `nimble start` - Run Enu in development mode
- `nimble build_and_start` - Build and run in one command
- `nimble edit` - Open project in Godot editor

### Distribution and Packaging
- `nimble dist` - Build complete distribution package for current platform
- `nimble dist_prereqs` - Build debug/release Godot versions and fonts
- `nimble dist_package` - Package distribution binaries

### Testing and Documentation
- `nimble test` - Run Godot-based tests
- `nimble docs` - Build documentation using nimibook
- `nimble clean` - Remove build artifacts

### Platform-Specific
- `nimble ios` - Build iOS package
- `nimble ios_prereqs` - Build Godot for iOS (requires macOS)

## Architecture

### Directory Structure

**Core Application (`src/`)**
- `src/enu.nim` - Entry point that imports all UI and node components
- `src/core.nim` - Core utilities, globals, and common imports
- `src/game.nim` - Main game loop and Godot integration
- `src/types.nim` - Type definitions for game state, tools, and model flags
- `src/models/` - Data models (bots, builds, players, signs, units, colors, ground)
- `src/controllers/` - Game logic controllers (node and script controllers)
- `src/ui/` - UI components (editor, console, toolbar, settings, etc.)
- `src/nodes/` - Godot node wrappers (player, bot, build, ground, sign nodes)

**Virtual Machine Environment (`vmlib/`)**
- `vmlib/enu/` - Enu-specific API for scripts (bots, builds, loops, state machine)
- `vmlib/stdlib/` - Copy of Nim stdlib for VM execution (auto-generated, don't modify)
- `vmlib/worlds/` - Default world templates and tutorials

**Godot Integration (`app/`)**
- `app/project.godot` - Godot project configuration
- `app/scenes/` - Godot scene files (.tscn)
- `app/components/` - Godot node scripts (.gdns) and scenes
- `app/textures/`, `app/materials/`, `app/shaders/` - Game assets

**Build System**
- `generated/` - Auto-generated Godot API bindings (created by build process)
- `vendor/` - Godot engine submodule
- `tools/build_helpers.nim` - Build automation utilities

### Key Concepts

**Dual Type System**: The project has two parallel type systems:
- Types in `src/` for the main application
- Corresponding types in `vmlib/enu/` for VM scripts
- These represent the same objects but in different contexts

**VM Integration**: User scripts run in the Nim VM, isolated from the main application. The VM has access to a curated API through `vmlib/enu/`.

**Godot Binding**: Uses nim-godot with auto-generated bindings from Godot 3.5 API. Generated code uses `camelCase` but project convention is `snake_case`.

**Model-View Architecture**: 
- Models handle data and state (using model_citizen library)
- Controllers manage game logic and coordinate between models and UI
- UI components handle presentation and user interaction

### Important Notes

- Always use `snake_case` for naming (despite generated bindings using `camelCase`)
- Use `nimble build` to verify changes compile correctly
- The project uses ZenContext for metrics and threading
- Scripts are Logo-inspired but use Nim syntax
- World data is stored as JSON with accompanying Nim scripts

## Coding Conventions

This project follows specific naming conventions inherited from the `model_citizen` library:

### Naming Style
- **Variables and procedures**: Use `snake_case` exclusively (e.g., `my_variable`, `process_changes`)
- **Types**: Use `UpperCamelCase` (e.g., `GameState`, `LocalStateFlags`)
- **Constants**: Use `snake_case` (e.g., `default_world`)
- **Fields**: Use `snake_case` (e.g., `player_color`, `world_dir`)

### Standard Library Usage
- **IMPORTANT**: When calling Nim standard library functions, always use `snake_case` style
- Use `init_hash_set()` instead of `initHashSet()`
- Use `to_flatty()` instead of `toFlatty()`
- Use `join_path()` instead of `joinPath()`

### Custom `?` Operator (Presence/Truth Testing)
The project uses a custom `?` operator from `model_citizen` for consistent presence checking:

```nim
# Usage examples
if ?my_ref_object:        # checks if not nil
if ?my_string:            # checks if not empty
if ?my_sequence:          # checks if length > 0
if ?my_option:            # checks if is_some
if ?my_number:            # checks if != 0
```

**Rule**: Always use `?` instead of manual nil checks, emptiness checks, or is_some calls.

### Logging Conventions
The project uses [Chronicles](https://github.com/status-im/nim-chronicles) for structured logging. Follow these patterns:

#### Basic Logging
```nim
info "Simple message"
info "Message with context", value = 42, name = "example"
```

#### Multi-Field Logging (Preferred)
```nim
# Good - single log line with multiple fields
info "[VERIFY] Systems initialized",
  vm = ?self.script_controller,
  node_controller = not self.node_controller.is_nil,
  world = state.config.world,
  level = state.config.level
```

#### Error Logging  
```nim
state.err "Error message", error = e.msg
```

**Rule**: Use structured logging with named fields rather than string concatenation. Group related information into single log statements when possible.

## Development Tools

### Verification Mode
The project includes a verification mode for testing system health:

```bash
# From project root
cd app && ../vendor/godot/bin/godot.osx.tools.arm64 --verbose scenes/game.tscn -- --verify
```

This mode:
- Tests VM initialization, controllers, and scene system
- Validates configuration loading and world/level directories
- Checks scene tree accessibility
- Outputs structured logs for comparison between Godot versions
- Automatically exits after verification

### Testing
- `nimble test` - Run Godot-based tests
- Always ensure tests pass before committing changes
- Use verification mode to validate core system functionality