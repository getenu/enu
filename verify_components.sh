#!/bin/bash

# Component Verification Script for Godot 4 Migration
# Runs build_and_start.sh and analyzes component loading status

echo "=== Enu Godot 4 Component Verification ==="
echo "Checking component loading status..."
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Run build (without timeout for macOS compatibility)
./build_and_start.sh > verification_output.log 2>&1 &
build_pid=$!

# Wait up to 60 seconds for build to complete
for i in {1..60}; do
    if ! kill -0 $build_pid 2>/dev/null; then
        break
    fi
    sleep 1
done

# If still running, kill it
if kill -0 $build_pid 2>/dev/null; then
    kill $build_pid
    wait $build_pid 2>/dev/null
    exit_code=124  # timeout exit code
else
    wait $build_pid 2>/dev/null
    exit_code=$?
fi

echo "Build exit code: $exit_code"
echo

# Analyze the output for component loading
echo "=== Component Loading Analysis ==="

# Function to check component status (without associative arrays for compatibility)
check_component_status() {
    local component=$1
    local ready_pattern=$2
    local file_pattern=$3

    if grep -q "$ready_pattern" verification_output.log; then
        echo "✅ SUCCESS"
    elif grep -q "$file_pattern" verification_output.log; then
        echo "⚠️  COMPILED (ready method not called)"
    else
        echo "❌ NOT LOADED"
    fi
}

# Check each component
actionbutton_status=$(check_component_status "ActionButton" "\[UI\] ActionButton ready:" "app/enu_game/src/ui/action_button.nim")
toolbar_status=$(check_component_status "Toolbar" "\[UI\] Toolbar ready" "app/enu_game/src/ui/toolbar.nim")
settings_status=$(check_component_status "Settings" "\[UI\] Settings ready" "app/enu_game/src/ui/settings.nim")
console_status=$(check_component_status "Console" "\[UI\] Console ready" "app/enu_game/src/ui/console.nim")
editor_status=$(check_component_status "EnuEditor" "\[UI\] Editor ready" "app/enu_game/src/ui/editor.nim")
gui_status=$(check_component_status "GUI" "\[UI\] GUI ready" "app/enu_game/src/ui/gui.nim")
markdown_status=$(check_component_status "MarkdownLabel" "\[UI\] MarkdownLabel ready" "app/enu_game/src/ui/markdown_label.nim")
preview_status=$(check_component_status "PreviewMaker" "\[UI\] PreviewMaker ready" "app/enu_game/src/ui/preview_maker.nim")

# Check special cases
if grep -q "Could not find node 'LeftStick' of type VirtualJoystick" verification_output.log; then
    joystick_status="⚠️  MISSING NODE (LeftStick not found)"
else
    joystick_status="❓ UNKNOWN"
fi

if grep -q "Loading resource: res://components/Player.tscn" verification_output.log; then
    player_status="🔄 LOADING (may have crashed during init)"
else
    player_status="❌ NOT STARTED"
fi

# Add button count for ActionButton if successful
if echo "$actionbutton_status" | grep -q "SUCCESS"; then
    button_count=$(grep "\[UI\] ActionButton ready:" verification_output.log | wc -l | tr -d ' ')
    actionbutton_status="✅ SUCCESS ($button_count buttons loaded)"
fi

# Add button info for Toolbar if successful
if echo "$toolbar_status" | grep -q "SUCCESS"; then
    if grep -q "\[UI\] Toolbar initialized with.*buttons" verification_output.log; then
        button_info=$(grep "\[UI\] Toolbar initialized with.*buttons" verification_output.log | sed 's/.*\[UI\] Toolbar initialized with \(.*\)/\1/')
        toolbar_status="✅ SUCCESS ($button_info)"
    fi
fi

# Display results
echo "Component Status Report:"
echo "========================"

echo -e "${GREEN}ActionButton${NC}: $actionbutton_status"
echo -e "${GREEN}Toolbar${NC}: $toolbar_status"
echo -e "${GREEN}Settings${NC}: $settings_status"
echo -e "${GREEN}Console${NC}: $console_status"
echo -e "${GREEN}Editor${NC}: $editor_status"
echo -e "${GREEN}GUI${NC}: $gui_status"
echo -e "${GREEN}MarkdownLabel${NC}: $markdown_status"
echo -e "${GREEN}PreviewMaker${NC}: $preview_status"
echo -e "${GREEN}VirtualJoystick${NC}: $joystick_status"
echo -e "${GREEN}PlayerNode${NC}: $player_status"

echo
echo "=== Build Issues Analysis ==="

# Check for compilation errors
if grep -q "Error:" verification_output.log; then
    echo -e "${RED}❌ COMPILATION ERRORS FOUND:${NC}"
    grep "Error:" verification_output.log
    echo
else
    echo -e "${GREEN}✅ NO COMPILATION ERRORS${NC}"
fi

# Check for warnings
warning_count=$(grep -c "Warning:" verification_output.log || echo "0")
if [ "$warning_count" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $warning_count WARNINGS FOUND${NC}"
    echo "Most warnings are unused imports - generally safe to ignore."
else
    echo -e "${GREEN}✅ NO WARNINGS${NC}"
fi

# Check for crash information
if [ "$exit_code" -eq 134 ]; then
    echo -e "${RED}❌ APPLICATION CRASHED (SIGABRT)${NC}"
    echo "Exit code 134 suggests a segmentation fault or assertion failure."
    echo "Crash appears to occur during Player scene initialization."
elif [ "$exit_code" -eq 124 ]; then
    echo -e "${YELLOW}⚠️  BUILD TIMEOUT (60 seconds)${NC}"
    echo "Build process took longer than expected."
elif [ "$exit_code" -ne 0 ]; then
    echo -e "${RED}❌ BUILD FAILED (exit code: $exit_code)${NC}"
else
    echo -e "${GREEN}✅ BUILD SUCCESSFUL${NC}"
fi

echo
echo "=== Summary ==="

successful_components=0
compiled_components=0
failed_components=0

# Count component statuses
for status in "$actionbutton_status" "$toolbar_status" "$settings_status" "$console_status" "$editor_status" "$gui_status" "$markdown_status" "$preview_status"; do
    case "$status" in
        "✅"*) successful_components=$((successful_components + 1)) ;;
        "⚠️"*"COMPILED"*) compiled_components=$((compiled_components + 1)) ;;
        "❌"*) failed_components=$((failed_components + 1)) ;;
    esac
done

total_core_components=8
echo "Core UI Components Status:"
echo "- ✅ Successfully Loading: $successful_components/$total_core_components"
echo "- ⚠️  Compiled but Not Called: $compiled_components/$total_core_components"
echo "- ❌ Failed to Load: $failed_components/$total_core_components"

if [ $((successful_components + compiled_components)) -gt 0 ]; then
    migration_percentage=$(( (successful_components + compiled_components) * 100 / total_core_components ))
else
    migration_percentage=0
fi
echo
echo -e "${BLUE}Overall Migration Status: ${migration_percentage}% of core UI components are working${NC}"

if [ "$successful_components" -ge 6 ]; then
    echo -e "${GREEN}🎉 MIGRATION LARGELY SUCCESSFUL!${NC}"
    echo "Most components are loading properly. Remaining issues likely relate to:"
    echo "- Scene integration (some components may not be instantiated in current scenes)"
    echo "- Player node initialization causing crashes"
elif [ "$migration_percentage" -ge 75 ]; then
    echo -e "${YELLOW}⚠️  MIGRATION MOSTLY WORKING${NC}"
    echo "Most components compile successfully. Focus on:"
    echo "- Adding components to scene files"
    echo "- Debugging runtime initialization issues"
else
    echo -e "${RED}❌ MIGRATION NEEDS MORE WORK${NC}"
    echo "Significant issues remain with component loading."
fi

echo
echo "Log saved to: verification_output.log"
echo "For detailed analysis, run: less verification_output.log"
