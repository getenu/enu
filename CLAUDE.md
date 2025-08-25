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