#!/bin/bash

echo "=== Rebuilding Game Extension ==="
echo "This rebuilds the Game extension and tests it"
echo

# Navigate to the Game extension directory
cd nim/enu_game || { echo "Error: Could not find nim/enu_game directory"; exit 1; }

echo "Building debug version..."
nim compile -f bootstrap.nim

if [ $? -eq 0 ]; then
    echo "✅ Debug build successful"
else
    echo "❌ Debug build failed"
    exit 1
fi

echo
echo "Building release version..."
nim compile -d:release -f bootstrap.nim

if [ $? -eq 0 ]; then
    echo "✅ Release build successful"
else
    echo "❌ Release build failed"
    exit 1
fi

# Go back to project root
cd ../..

echo
echo "Setting up extension for testing..."
rm -f *.gdextension
cp nim/enu_game/Enugame.gdextension .

echo
echo "Testing rebuilt Game extension..."
echo "Running: ../vendor/godot/bin/godot.macos.editor.arm64 --verbose --headless game_scene.tscn --quit-after 3"
echo

../vendor/godot/bin/godot.macos.editor.arm64 --verbose --headless verify_scene.tscn --quit-after 3 | grep -E "(\[VERIFY\]|ERROR.*Game|Game ready)"
