# Enu UI System Documentation

## Overview

This document describes the layout and behavior of Enu's user interface system, designed to work across desktop and mobile devices with adaptive layouts.

## Core Layout Principles

### Toolbar
- **Position**: Always centered at the bottom of the screen
- **Behavior**: Fixed position - no other UI elements should impact its size or position
- **Overlays**: Console, editor, right panel, and settings panel can overlay the toolbar
- **Sizing**: 
  - Configurable size with minimum and maximum values
  - Can only get as wide as the screen
  - Settings can be set larger, but growth stops at screen edges regardless of setting value

### Left Panel (Editor + Console)
- **Components**: Contains both editor and console in a vertical layout
- **Editor**: 
  - Takes full screen height when console is hidden
  - Shrinks vertically to make room when console is visible
  - Always maintains its position at the top of the left panel
- **Console**:
  - Fixed height (does not resize)
  - Pushes editor upward when visible
  - Positioned at bottom of left panel
- **Visibility**: Can show editor only, console only, or both simultaneously

### Right Panel
- **Width**: Normally takes exactly 50% of screen width
- **Height**: Always takes full screen height
- **Narrow Device Behavior**: 
  - On narrow screens (e.g., phone in portrait): takes up almost the whole screen
  - Small area left exposed so users can switch between left/right panels
- **Content**: Displays subset of markdown content
- **No Sharing**: Does not have to share space with other components

### Settings Window
- **Position**: Always appears on top of all other elements
- **Trigger**: Gear icon at top right (below right panel if right panel is visible)
- **Dynamic Sizing**: Window size adapts to content size, primarily based on font size
- **Font Size Scaling**: As font size increases, window gets larger
- **Conditional Content**: Some sections (like "remote server address") may not always be visible
- **Responsive Layout**:
  - Default: Two columns of settings
  - Narrow + tall screen: Collapses to single column when window would exceed screen width
  - Can expand past screen bounds, but maximum font size prevents excessive size

### Layout Animations

#### Settings Window
- **Element Removal**: Bottom of window slides up to hide element before making it invisible
- **Element Addition**: Bottom slides back down to reveal new elements
- **Smooth Transitions**: All changes animated for better UX

#### New Level Creation
- **State Change**: When "New level" is selected from level dropdown
- **Content Replacement**: Rest of settings content disappears
- **New UI**: Replaced with label, text field, and button for level name input
- **Isolation**: Only level creation controls remain visible

## Device Adaptations

### Desktop
- Full layout with all panels at their preferred sizes
- Toolbar centered, panels at 50% width each

### Mobile Portrait
- Right panel takes almost full width when visible
- Left panel similarly expanded when active
- Small exposed areas allow panel switching
- Settings collapse to single column

### Mobile Landscape
- Maintains desktop-like proportions where possible
- Settings may still use two-column layout

## Implementation Notes

### Godot 4 Migration Considerations
- Layout uses Control nodes with proper anchoring
- VBoxContainer for left panel editor/console stacking
- GridContainer for settings layout with responsive column management
- Proper size flags for dynamic resizing behavior

### Key Size Flags
- **Editor**: `size_flags_vertical = 3` (expand + fill) with `stretch_ratio = 2.0`
- **Console**: `size_flags_vertical = 1` (fill only, no expand) - maintains fixed height
- **Panels**: Use anchoring and percentage-based widths for responsive behavior

## Current Status (Godot 4 Migration)

### ✅ **Working Components** (Verified via screenshot 2025-09-10T21-50-52.png)
- ✅ **Basic layout structure** - All panels correctly positioned
- ✅ **Left panel functionality** - Editor and console both visible and working
- ✅ **Console system** - Debug messages displaying correctly, animations working
- ✅ **Editor functionality** - Code editing visible with syntax highlighting and line numbers
- ✅ **Toolbar positioning** - All 8 tool buttons visible at bottom center
- ✅ **3D viewport** - Game world rendering correctly with player and voxel terrain
- ✅ **Touch controls** - Virtual joystick visible in bottom left
- ✅ **Forced visibility system** - All panels can be made visible for debugging

### ⚠️ **Partial Functionality** 
- ⚠️ **Settings panel** - Panel container visible but content missing (shows empty dark area)
  - **Root cause**: `settings_container` and `tween` components not found in scene tree
  - **Status**: Signal connections work, but UI elements are missing
  - **Logs show**: `[UI] ✗ Settings component not found: settings_container`

### 📝 **Outstanding Items**
- 📝 Fix settings panel content rendering (components missing from scene)
- 📝 Implement responsive width behavior for narrow screens  
- 📝 Implement settings window animations (depends on fixing content first)

## Testing and Verification

### Screenshot Mode (✅ Working)
- **Command**: `../vendor/godot/bin/godot.macos.editor.arm64 --screenshot scenes/game.tscn`
- **Function**: Takes screenshot after 5 seconds, saves to work directory, then quits
- **Output**: `screenshot_YYYY-MM-DD'T'HH-mm-ss.png` in `/Volumes/Data/scott/Library/Application Support/enu/`
- **Critical**: All UI changes must be verified by viewing screenshots before considering work complete